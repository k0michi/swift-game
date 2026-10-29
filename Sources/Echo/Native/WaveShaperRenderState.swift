// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
import Foundation

// The filters a WaveShaperNode oversamples with, which keep each channel's
// recent samples from one render quantum to the next. Used only by the
// rendering thread.
final class WaveShaperRenderState: @unchecked Sendable {
    // Up-sampling to 2x and then to 4x, and down-sampling from 4x and then
    // from 2x.
    private let upTo2x: HalfBandFilter
    private let upTo4x: HalfBandFilter
    private let downFrom4x: HalfBandFilter
    private let downFrom2x: HalfBandFilter
    // The oversampled signal at 2x and at 4x.
    private let at2x: UnsafeMutableBufferPointer<Float>
    private let at4x: UnsafeMutableBufferPointer<Float>
    // What the filters' recent samples are from, so that a change starts
    // them from silence.
    private var filtered: OverSampleType = .none

    init(channelCapacity: Int, quantumSize: Int) {
        upTo2x = HalfBandFilter(channelCapacity: channelCapacity, frameCapacity: 2 * quantumSize)
        upTo4x = HalfBandFilter(channelCapacity: channelCapacity, frameCapacity: 4 * quantumSize)
        downFrom4x = HalfBandFilter(channelCapacity: channelCapacity, frameCapacity: 4 * quantumSize)
        downFrom2x = HalfBandFilter(channelCapacity: channelCapacity, frameCapacity: 2 * quantumSize)
        at2x = .allocate(capacity: 2 * quantumSize)
        at2x.initialize(repeating: 0)
        at4x = .allocate(capacity: 4 * quantumSize)
        at4x.initialize(repeating: 0)
    }

    deinit {
        at2x.deinitialize()
        at2x.deallocate()
        at4x.deinitialize()
        at4x.deallocate()
    }

    // The output has as many channels as the input.
    func render(
        input: AudioRenderQuantum,
        output: AudioRenderQuantum,
        curve: [Float]?,
        oversample: OverSampleType
    ) {
        output.setChannelCount(input.channelCount)
        guard let curve else {
            output.copy(from: input)
            filtered = .none
            return
        }
        if oversample != filtered {
            // One at a time, as an array of them would be allocated.
            upTo2x.reset()
            upTo4x.reset()
            downFrom4x.reset()
            downFrom2x.reset()
            filtered = oversample
        }
        let frameCount = input.frameCount
        curve.withUnsafeBufferPointer { curve in
            for channel in 0 ..< input.channelCount {
                let source = input.channelData(channel)
                let destination = output.channelData(channel)
                switch oversample {
                case .none:
                    for frame in 0 ..< frameCount {
                        destination[frame] = Self.shape(source[frame], curve: curve)
                    }
                case .`2x`:
                    upTo2x.upsample(channel: channel, source, into: at2x)
                    Self.shape(at2x, count: 2 * frameCount, curve: curve)
                    downFrom2x.downsample(channel: channel, at2x, count: 2 * frameCount, into: destination)
                case .`4x`:
                    upTo2x.upsample(channel: channel, source, into: at2x)
                    upTo4x.upsample(channel: channel, UnsafeMutableBufferPointer(rebasing: at2x[0 ..< 2 * frameCount]),
                                    into: at4x)
                    Self.shape(at4x, count: 4 * frameCount, curve: curve)
                    downFrom4x.downsample(channel: channel, at4x, count: 4 * frameCount, into: at2x)
                    downFrom2x.downsample(channel: channel, at2x, count: 2 * frameCount, into: destination)
                }
            }
        }
    }

    private static func shape(_ samples: UnsafeMutableBufferPointer<Float>, count: Int, curve: UnsafeBufferPointer<Float>) {
        for index in 0 ..< count {
            samples[index] = shape(samples[index], curve: curve)
        }
    }

    // The specification's interpolation: the curve's values are spread evenly
    // over [-1, 1], and inputs beyond take its first or last value. It does
    // not define NaN, which stays NaN.
    static func shape(_ input: Float, curve: UnsafeBufferPointer<Float>) -> Float {
        guard !input.isNaN else { return input }
        let last = curve.count - 1
        let v = Double(last) / 2 * (Double(input) + 1)
        if v < 0 { return curve[0] }
        if v >= Double(last) { return curve[last] }
        let k = Int(v)
        let f = Float(v - Double(k))
        return (1 - f) * curve[k] + f * curve[k + 1]
    }
}

// A low-pass filter whose cutoff is half the Nyquist frequency of the rate it
// runs at: the Nyquist frequency of the rate half as fast. Up-sampling by two
// fills in between the samples with it, and down-sampling by two removes
// what would alias. Each channel keeps the samples the next block needs.
private final class HalfBandFilter {
    // A windowed sinc, with Blackman's window, of unit gain at 0 Hz.
    private static let taps: [Float] = {
        let length = 31
        let middle = length / 2
        var taps = (0 ..< length).map { index -> Double in
            let offset = Double(index - middle)
            let sinc = offset == 0 ? 0.5 : sin(.pi * offset / 2) / (.pi * offset)
            let phase = 2 * .pi * Double(index) / Double(length - 1)
            return sinc * (0.42 - 0.5 * cos(phase) + 0.08 * cos(2 * phase))
        }
        let sum = taps.reduce(0, +)
        taps = taps.map { $0 / sum }
        return taps.map(Float.init)
    }()

    private let historyLength = taps.count - 1
    private let history: UnsafeMutableBufferPointer<Float>
    // The channel's history followed by the block being filtered.
    private let window: UnsafeMutableBufferPointer<Float>

    init(channelCapacity: Int, frameCapacity: Int) {
        history = .allocate(capacity: channelCapacity * historyLength)
        history.initialize(repeating: 0)
        window = .allocate(capacity: historyLength + frameCapacity)
        window.initialize(repeating: 0)
    }

    deinit {
        history.deinitialize()
        history.deallocate()
        window.deinitialize()
        window.deallocate()
    }

    func reset() {
        history.update(repeating: 0)
    }

    // Doubles the rate of `source` into `destination`: the samples with zeros
    // between them, at twice their level to keep it, filtered.
    func upsample(
        channel: Int,
        _ source: UnsafeMutableBufferPointer<Float>,
        into destination: UnsafeMutableBufferPointer<Float>
    ) {
        for (index, sample) in source.enumerated() {
            destination[2 * index] = 2 * sample
            destination[2 * index + 1] = 0
        }
        filter(channel: channel, destination, count: 2 * source.count)
    }

    // Halves the rate of the first `count` samples of `source`, which it
    // filters in place, into `destination`.
    func downsample(
        channel: Int,
        _ source: UnsafeMutableBufferPointer<Float>,
        count: Int,
        into destination: UnsafeMutableBufferPointer<Float>
    ) {
        filter(channel: channel, source, count: count)
        for index in 0 ..< count / 2 {
            destination[index] = source[2 * index]
        }
    }

    // Filters the first `count` samples in place.
    private func filter(channel: Int, _ samples: UnsafeMutableBufferPointer<Float>, count: Int) {
        let channelHistory = UnsafeMutableBufferPointer(
            rebasing: history[channel * historyLength ..< (channel + 1) * historyLength]
        )
        for index in 0 ..< historyLength {
            window[index] = channelHistory[index]
        }
        for index in 0 ..< count {
            window[historyLength + index] = samples[index]
        }
        Self.taps.withUnsafeBufferPointer { taps in
            for index in 0 ..< count {
                var sum: Float = 0
                for tap in 0 ..< taps.count {
                    sum += taps[tap] * window[index + historyLength - tap]
                }
                samples[index] = sum
            }
        }
        for index in 0 ..< historyLength {
            channelHistory[index] = window[count + index]
        }
    }
}
#endif
