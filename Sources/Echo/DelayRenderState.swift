final class DelayRenderState: @unchecked Sendable {
    private let frameCapacity: Int
    private let channelCapacity: Int
    private let maxDelayTime: Float
    private let samples: UnsafeMutableBufferPointer<Float>
    private let channelCounts: UnsafeMutableBufferPointer<UInt8>
    private let remixSource: AudioRenderQuantum
    private let remixDestination: AudioRenderQuantum
    private var writePosition = 0
    private var nextFrame: UInt64?

    init(maxDelayTime: Double, sampleRate: Float, channelCapacity: Int, quantumSize: Int) {
        frameCapacity = max(Int((maxDelayTime * Double(sampleRate)).rounded(.up)), quantumSize) + 2
        self.channelCapacity = channelCapacity
        self.maxDelayTime = Float(maxDelayTime)
        samples = .allocate(capacity: frameCapacity * channelCapacity)
        samples.initialize(repeating: 0)
        channelCounts = .allocate(capacity: frameCapacity)
        channelCounts.initialize(repeating: 0)
        remixSource = AudioRenderQuantum(channelCapacity: channelCapacity, frameCount: 1)
        remixDestination = AudioRenderQuantum(channelCapacity: channelCapacity, frameCount: 1)
    }

    deinit {
        samples.deinitialize()
        samples.deallocate()
        channelCounts.deinitialize()
        channelCounts.deallocate()
    }

    func render(
        input: AudioRenderQuantum,
        output: AudioRenderQuantum,
        parameter: AudioParamTimeline,
        modulation: AudioRenderQuantum?,
        interpretation: ChannelInterpretation,
        frame: UInt64
    ) {
        precondition(input.channelCount <= channelCapacity)
        skipToFrame(frame)
        output.setChannelCount(outputChannelCount(
            inputCount: input.channelCount, parameter: parameter, modulation: modulation,
            frame: frame, frameCount: input.frameCount, minimumDelayFrames: 0
        ))
        for sample in 0 ..< input.frameCount {
            let position = (writePosition + sample) % frameCapacity
            for channel in 0 ..< input.channelCount {
                samples[channel * frameCapacity + position] = input.channelData(channel)[sample]
            }
            channelCounts[position] = UInt8(input.channelCount)
            let delayed = delayedPosition(
                sample: sample, parameter: parameter, modulation: modulation,
                frame: frame, minimumDelayFrames: 0
            )
            renderSample(delayed, sample: sample, output: output, interpretation: interpretation)
        }
        writePosition = (writePosition + input.frameCount) % frameCapacity
        nextFrame = frame + UInt64(input.frameCount)
    }

    func read(
        output: AudioRenderQuantum,
        parameter: AudioParamTimeline,
        modulation: AudioRenderQuantum?,
        interpretation: ChannelInterpretation,
        frame: UInt64
    ) {
        skipToFrame(frame)
        let minimumDelayFrames = output.frameCount
        output.setChannelCount(outputChannelCount(
            inputCount: nil, parameter: parameter, modulation: modulation,
            frame: frame, frameCount: output.frameCount, minimumDelayFrames: minimumDelayFrames
        ))
        for sample in 0 ..< output.frameCount {
            let delayed = delayedPosition(
                sample: sample, parameter: parameter, modulation: modulation,
                frame: frame, minimumDelayFrames: minimumDelayFrames
            )
            renderSample(delayed, sample: sample, output: output, interpretation: interpretation)
        }
    }

    func write(input: AudioRenderQuantum, frame: UInt64) {
        precondition(input.channelCount <= channelCapacity)
        for sample in 0 ..< input.frameCount {
            let position = (writePosition + sample) % frameCapacity
            for channel in 0 ..< input.channelCount {
                samples[channel * frameCapacity + position] = input.channelData(channel)[sample]
            }
            channelCounts[position] = UInt8(input.channelCount)
        }
        writePosition = (writePosition + input.frameCount) % frameCapacity
        nextFrame = frame + UInt64(input.frameCount)
    }

    private func outputChannelCount(
        inputCount: Int?,
        parameter: AudioParamTimeline,
        modulation: AudioRenderQuantum?,
        frame: UInt64,
        frameCount: Int,
        minimumDelayFrames: Int
    ) -> Int {
        var count = 1
        for sample in 0 ..< frameCount {
            let delayed = delayedPosition(
                sample: sample, parameter: parameter, modulation: modulation,
                frame: frame, minimumDelayFrames: minimumDelayFrames
            )
            let newestCount = delayed.wholeFrames <= sample
                ? inputCount ?? Int(channelCounts[delayed.newest])
                : Int(channelCounts[delayed.newest])
            count = max(count, newestCount)
            if delayed.fraction > 0 {
                let olderCount = delayed.wholeFrames < sample
                    ? inputCount ?? Int(channelCounts[delayed.older])
                    : Int(channelCounts[delayed.older])
                count = max(count, olderCount)
            }
        }
        return count
    }

    private func delayedPosition(
        sample: Int,
        parameter: AudioParamTimeline,
        modulation: AudioRenderQuantum?,
        frame: UInt64,
        minimumDelayFrames: Int
    ) -> (newest: Int, older: Int, fraction: Float, wholeFrames: Int) {
        let modulationIndex = parameter.automationRate == .kRate ? 0 : sample
        let modulationValue = modulation?.channelData(0)[modulationIndex] ?? 0
        let delayTime = parameter.computedValue(
            at: frame + UInt64(sample), quantumStart: frame, modulation: modulationValue
        )
        let delayedFrames = max(
            Double(min(delayTime, maxDelayTime)) * Double(parameter.sampleRate),
            Double(minimumDelayFrames)
        )
        let wholeFrames = Int(delayedFrames)
        let fraction = Float(delayedFrames - Double(wholeFrames))
        let newest = (writePosition + sample - wholeFrames + frameCapacity) % frameCapacity
        return (newest, (newest - 1 + frameCapacity) % frameCapacity, fraction, wholeFrames)
    }

    private func renderSample(
        _ delayed: (newest: Int, older: Int, fraction: Float, wholeFrames: Int),
        sample: Int,
        output: AudioRenderQuantum,
        interpretation: ChannelInterpretation
    ) {
        mixStoredFrame(at: delayed.newest, interpretation: interpretation, outputCount: output.channelCount)
        for channel in 0 ..< output.channelCount {
            output.channelData(channel)[sample] = remixDestination.channelData(channel)[0] * (1 - delayed.fraction)
        }
        guard delayed.fraction > 0 else { return }
        mixStoredFrame(at: delayed.older, interpretation: interpretation, outputCount: output.channelCount)
        for channel in 0 ..< output.channelCount {
            output.channelData(channel)[sample] += remixDestination.channelData(channel)[0] * delayed.fraction
        }
    }

    private func mixStoredFrame(
        at position: Int,
        interpretation: ChannelInterpretation,
        outputCount: Int
    ) {
        let storedCount = Int(channelCounts[position])
        remixDestination.setChannelCount(outputCount)
        remixDestination.clear()
        guard storedCount > 0 else { return }
        remixSource.setChannelCount(storedCount)
        for channel in 0 ..< storedCount {
            remixSource.channelData(channel)[0] = samples[channel * frameCapacity + position]
        }
        ChannelMixer.mix(remixSource, into: remixDestination, interpretation: interpretation)
    }

    private func skipToFrame(_ frame: UInt64) {
        guard let nextFrame, frame > nextFrame else { return }
        let missing = frame - nextFrame
        if missing >= UInt64(frameCapacity) {
            channelCounts.update(repeating: 0)
            writePosition = (writePosition + Int(missing % UInt64(frameCapacity))) % frameCapacity
            return
        }
        for _ in 0 ..< missing {
            channelCounts[writePosition] = 0
            writePosition = (writePosition + 1) % frameCapacity
        }
    }
}
