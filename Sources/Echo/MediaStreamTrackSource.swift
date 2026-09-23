import Atomics
import Foundation

final class MediaStreamTrackSource: @unchecked Sendable {
    let sampleRate: Float
    let channelCount: UInt32
    let label: String
    let ended = ManagedAtomic(false)

    private let capacity = 16_384
    private let samples: UnsafeMutableBufferPointer<Float>
    private let lock = NSLock()
    private let onStop: @Sendable () -> Void
    private var writtenFrames: UInt64 = 0
    private var liveTracks = 1
    private var captureStopped = false

    init(
        sampleRate: Float,
        channelCount: UInt32,
        label: String,
        onStop: @escaping @Sendable () -> Void
    ) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.label = label
        self.onStop = onStop
        samples = .allocate(capacity: capacity * Int(channelCount))
        samples.initialize(repeating: 0)
    }

    deinit {
        samples.deinitialize()
        samples.deallocate()
    }

    func retainTrack() {
        lock.lock()
        liveTracks += 1
        lock.unlock()
    }

    func releaseTrack() {
        lock.lock()
        liveTracks -= 1
        let shouldStop = liveTracks == 0 && !captureStopped
        if shouldStop { captureStopped = true }
        lock.unlock()
        if shouldStop { onStop() }
    }

    func end() {
        lock.lock()
        let shouldStop = !captureStopped
        captureStopped = true
        ended.store(true, ordering: .releasing)
        lock.unlock()
        if shouldStop { onStop() }
    }

    func appendInterleaved(_ input: UnsafeBufferPointer<Float>) -> Int {
        guard !ended.load(ordering: .acquiring),
              input.count.isMultiple(of: Int(channelCount)) else { return 0 }
        lock.lock()
        defer { lock.unlock() }
        let channels = Int(channelCount)
        let frames = input.count / channels
        for frame in 0 ..< frames {
            let destination = Int((writtenFrames + UInt64(frame)) % UInt64(capacity)) * channels
            let source = frame * channels
            for channel in 0 ..< channels {
                samples[destination + channel] = input[source + channel]
            }
        }
        writtenFrames += UInt64(frames)
        return frames
    }

    func currentFrame() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return writtenFrames
    }

    func render(
        into output: AudioRenderQuantum,
        cursor: inout Double,
        outputSampleRate: Float,
        silent: Bool
    ) {
        output.setChannelCount(Int(channelCount))
        lock.lock()
        defer { lock.unlock() }
        let oldestFrame = writtenFrames > UInt64(capacity) ? writtenFrames - UInt64(capacity) : 0
        cursor = max(cursor, Double(oldestFrame))
        let increment = Double(sampleRate) / Double(outputSampleRate)
        for frame in 0 ..< output.frameCount {
            let inputFrame = UInt64(cursor)
            guard inputFrame < writtenFrames else { break }
            if !silent {
                let fraction = Float(cursor - Double(inputFrame))
                let nextFrame = min(inputFrame + 1, writtenFrames - 1)
                let currentIndex = Int(inputFrame % UInt64(capacity)) * Int(channelCount)
                let nextIndex = Int(nextFrame % UInt64(capacity)) * Int(channelCount)
                for channel in 0 ..< Int(channelCount) {
                    let current = samples[currentIndex + channel]
                    output.channelData(channel)[frame] = current
                        + (samples[nextIndex + channel] - current) * fraction
                }
            }
            cursor += increment
        }
        cursor = min(cursor, Double(writtenFrames))
    }
}
