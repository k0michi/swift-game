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
        graph.invalidate()
        context.graphDidChange()
    }

    public func setChannelCountMode(_ channelCountMode: ChannelCountMode) {
        self.channelCountMode = channelCountMode
        graph.invalidate()
        context.graphDidChange()
    }

    public func setChannelInterpretation(_ channelInterpretation: ChannelInterpretation) {
        self.channelInterpretation = channelInterpretation
        graph.invalidate()
        context.graphDidChange()
    }

    @discardableResult
    public func connect(_ destinationNode: AudioNode, output: UInt32 = 0, input: UInt32 = 0) throws -> AudioNode {
        guard context === destinationNode.context else { throw WebAudioError.invalidAccess }
        guard output < numberOfOutputs, input < destinationNode.numberOfInputs else {
            throw WebAudioError.indexSize
        }
        try graph.connect(self, to: destinationNode, output: output, input: input)
        context.graphDidChange()
        return destinationNode
    }

    public func disconnect() {
        graph.disconnect(self)
        context.graphDidChange()
    }

    public func disconnect(output: UInt32) throws {
        guard output < numberOfOutputs else { throw WebAudioError.indexSize }
        graph.disconnect(self, output: output)
        context.graphDidChange()
    }

    public func disconnect(_ destinationNode: AudioNode) throws {
        guard graph.disconnect(self, from: destinationNode) else { throw WebAudioError.invalidAccess }
        context.graphDidChange()
    }

    var audioParams: [AudioParam] { [] }

    public func connect(_ destinationParam: AudioParam, output: UInt32 = 0) throws {
        guard context === destinationParam.context else { throw WebAudioError.invalidAccess }
        guard output < numberOfOutputs else { throw WebAudioError.indexSize }
        graph.connect(self, to: destinationParam, output: output)
        context.graphDidChange()
    }

    public func disconnect(_ destinationParam: AudioParam) throws {
        guard graph.disconnect(self, from: destinationParam) else { throw WebAudioError.invalidAccess }
        context.graphDidChange()
    }

    // TODO: Add the remaining Web IDL disconnect overloads.
}
