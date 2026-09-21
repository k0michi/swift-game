// Prepared on the control actor, then used exclusively by one rendering thread.
final class AudioRenderPlan: @unchecked Sendable {
    enum Processor: Sendable {
        case passThrough
        case constant(
            startFrame: UInt64?,
            stopFrame: UInt64?,
            value: Float,
            defaultValue: Float,
            minValue: Float,
            maxValue: Float,
            paramSources: [Int]
        )
    }

    struct NodeConfiguration: Sendable {
        let inputChannelCount: Int?
        let outputChannelCount: Int
        let interpretation: ChannelInterpretation
        let sources: [Int]
        let isMuted: Bool
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
                AudioRenderQuantum(channelCapacity: $0, frameCount: frameCount)
            }
            output = AudioRenderQuantum(
                channelCapacity: configuration.outputChannelCount,
                frameCount: frameCount
            )
            if case let .constant(_, _, _, _, _, _, sources) = configuration.processor, !sources.isEmpty {
                paramInput = AudioRenderQuantum(channelCapacity: 1, frameCount: frameCount)
            } else {
                paramInput = nil
            }
        }
    }

    let frameCount: Int
    private let slots: [Slot]

    init(configurations: [NodeConfiguration], frameCount: Int) {
        self.frameCount = frameCount
        slots = configurations.map { Slot(configuration: $0, frameCount: frameCount) }
    }

    func render(at frame: UInt64, into buffer: AudioBuffer, offset: Int) throws {
        for slot in slots {
            slot.input?.clear()
            slot.output.clear()

            let configuration = slot.configuration
            if configuration.isMuted { continue }

            if let input = slot.input {
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
                if let input = slot.input { slot.output.copy(from: input) }
            case let .constant(startFrame, stopFrame, value, defaultValue, minValue, maxValue, paramSources):
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
                    let modulation = slot.paramInput.map { $0.channelData(0)[index] } ?? 0
                    let sum = value + modulation
                    samples[index] = min(max(sum.isNaN ? defaultValue : sum, minValue), maxValue)
                }
            }
        }

        guard let destination = slots.last?.output else { return }
        for channel in 0 ..< destination.channelCount {
            let target = try buffer.getChannelData(UInt32(channel))
            let source = destination.channelData(channel)
            for sample in 0 ..< frameCount {
                target[offset + sample] = source[sample]
            }
        }
    }
}
