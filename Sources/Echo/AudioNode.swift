@MainActor
public class AudioNode {
    public let context: BaseAudioContext
    public let numberOfInputs: UInt32
    public let numberOfOutputs: UInt32

    public private(set) var channelCount: UInt32
    public private(set) var channelCountMode: ChannelCountMode
    public private(set) var channelInterpretation: ChannelInterpretation

    let graph: AudioGraph

    init(
        context: BaseAudioContext,
        numberOfInputs: UInt32,
        numberOfOutputs: UInt32,
        channelCount: UInt32,
        channelCountMode: ChannelCountMode,
        channelInterpretation: ChannelInterpretation
    ) {
        self.context = context
        self.numberOfInputs = numberOfInputs
        self.numberOfOutputs = numberOfOutputs
        self.channelCount = channelCount
        self.channelCountMode = channelCountMode
        self.channelInterpretation = channelInterpretation
        graph = context.graph
    }

    public func setChannelCount(_ channelCount: UInt32) throws {
        guard (1 ... AudioBuffer.maximumNumberOfChannels).contains(channelCount) else {
            throw WebAudioError.indexSize
        }

        self.channelCount = channelCount
    }

    public func setChannelCountMode(_ channelCountMode: ChannelCountMode) {
        self.channelCountMode = channelCountMode
    }

    public func setChannelInterpretation(_ channelInterpretation: ChannelInterpretation) {
        self.channelInterpretation = channelInterpretation
    }

    // TODO: Implement connect and disconnect with control messages.
}
