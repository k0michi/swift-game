// Prepared on the control actor, then used exclusively by one rendering thread.
final class AudioRenderPlan: @unchecked Sendable {
    enum Processor: Sendable {
        case passThrough
        case constant(
            startFrame: UInt64?,
            stopFrame: UInt64?,
            parameter: AudioParamTimeline,
            paramSources: [Int]
        )
        case delay(
            state: DelayRenderState,
            parameter: AudioParamTimeline,
            paramSources: [Int]
        )
    }

    struct NodeConfiguration: Sendable {
        let inputChannelCount: Int?
        let outputChannelCount: Int
        let interpretation: ChannelInterpretation
        let channelCount: Int
        let channelCountMode: ChannelCountMode
        let sources: [Int]
        let isMuted: Bool
        let isCycleBreaker: Bool
        let processor: Processor
    }

    private final class Slot {
        let configuration: NodeConfiguration
        let input: AudioRenderQuantum?
        let output: AudioRenderQuantum
        let paramInput: AudioRenderQuantum?

        init(configuration: NodeConfiguration, frameCount: Int) {
            self.configuration = configuration
            input = configuration.inputChannelCount.map {
                AudioRenderQuantum(
                    channelCapacity: Self.isDelay(configuration.processor) || Self.isDestination(configuration.processor)
                        ? Int(AudioBuffer.maximumNumberOfChannels) : $0,
                    frameCount: frameCount, channelCount: $0
                )
            }
            output = AudioRenderQuantum(
                channelCapacity: Self.isDelay(configuration.processor)
                    ? Int(AudioBuffer.maximumNumberOfChannels) : configuration.outputChannelCount,
                frameCount: frameCount, channelCount: configuration.outputChannelCount
            )
            switch configuration.processor {
            case let .constant(_, _, _, sources), let .delay(_, _, sources):
                paramInput = sources.isEmpty ? nil : AudioRenderQuantum(channelCapacity: 1, frameCount: frameCount)
            case .passThrough:
                paramInput = nil
            }
        }

        private static func isDelay(_ processor: Processor) -> Bool {
            if case .delay = processor { return true }
            return false
        }

        private static func isDestination(_ processor: Processor) -> Bool {
            if case .passThrough = processor { return true }
            return false
        }
    }

    let frameCount: Int
    let destinationChannelCount: Int
    private let slots: [Slot]
    private let destinationIndex: Int

    init(configurations: [NodeConfiguration], frameCount: Int, destinationIndex: Int) {
        self.frameCount = frameCount
        self.destinationIndex = destinationIndex
        destinationChannelCount = configurations[destinationIndex].outputChannelCount
        slots = configurations.map { Slot(configuration: $0, frameCount: frameCount) }
    }

    func render(at frame: UInt64, into target: OfflineRenderTarget, offset: Int) {
        for slot in slots {
            slot.input?.clear()
            slot.output.clear()

            let configuration = slot.configuration
            if configuration.isMuted { continue }

            if let input = slot.input, !configuration.isCycleBreaker {
                configureInput(input, for: configuration)
                input.clear()
                for sourceIndex in configuration.sources {
                    ChannelMixer.mix(
                        slots[sourceIndex].output,
                        into: input,
                        interpretation: configuration.interpretation
                    )
                }
            }

            switch configuration.processor {
            case .passThrough:
                if let input = slot.input {
                    ChannelMixer.mix(input, into: slot.output, interpretation: configuration.interpretation)
                }
            case let .constant(startFrame, stopFrame, parameter, paramSources):
                guard let startFrame else { continue }
                slot.paramInput?.clear()
                if let paramInput = slot.paramInput {
                    for sourceIndex in paramSources {
                        ChannelMixer.mix(slots[sourceIndex].output, into: paramInput, interpretation: .speakers)
                    }
                }

                let samples = slot.output.channelData(0)
                for index in samples.indices {
                    let currentFrame = frame + UInt64(index)
                    guard currentFrame >= startFrame, stopFrame.map({ currentFrame < $0 }) ?? true else {
                        continue
                    }
                    let modulationIndex = parameter.automationRate == .kRate ? 0 : index
                    let modulation = slot.paramInput.map { $0.channelData(0)[modulationIndex] } ?? 0
                    samples[index] = parameter.computedValue(
                        at: currentFrame,
                        quantumStart: frame,
                        modulation: modulation
                    )
                }
            case let .delay(state, parameter, paramSources):
                slot.paramInput?.clear()
                if let paramInput = slot.paramInput {
                    for sourceIndex in paramSources {
                        ChannelMixer.mix(slots[sourceIndex].output, into: paramInput, interpretation: .speakers)
                    }
                }
                if let input = slot.input {
                    if configuration.isCycleBreaker {
                        state.read(output: slot.output, parameter: parameter,
                                   modulation: slot.paramInput, interpretation: configuration.interpretation,
                                   frame: frame)
                    } else {
                        state.render(input: input, output: slot.output, parameter: parameter,
                                     modulation: slot.paramInput, interpretation: configuration.interpretation,
                                     frame: frame)
                    }
                }
            }
        }

        for slot in slots where slot.configuration.isCycleBreaker && !slot.configuration.isMuted {
            guard let input = slot.input, case let .delay(state, _, _) = slot.configuration.processor else { continue }
            configureInput(input, for: slot.configuration)
            input.clear()
            for sourceIndex in slot.configuration.sources {
                ChannelMixer.mix(slots[sourceIndex].output, into: input,
                                 interpretation: slot.configuration.interpretation)
            }
            state.write(input: input, frame: frame)
        }

        let destination = slots[destinationIndex].output
        for channel in 0 ..< destination.channelCount {
            let channelTarget = target.channelData(channel)
            let source = destination.channelData(channel)
            for sample in 0 ..< frameCount {
                channelTarget[offset + sample] = source[sample]
            }
        }
    }

    private func configureInput(_ input: AudioRenderQuantum, for configuration: NodeConfiguration) {
        var maximum = 1
        for sourceIndex in configuration.sources {
            maximum = max(maximum, slots[sourceIndex].output.channelCount)
        }
        let count: Int
        switch configuration.channelCountMode {
        case .max: count = maximum
        case .clampedMax: count = min(maximum, configuration.channelCount)
        case .explicit: count = configuration.channelCount
        }
        input.setChannelCount(count)
    }
}
