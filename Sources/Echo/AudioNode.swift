open class AudioNode {
    public let context: BaseAudioContext
    public let numberOfInputs: UInt32
    public let numberOfOutputs: UInt32
    public var channelCount: UInt32 {
        didSet { graph.setChannelCount(id: id, value: channelCount) }
    }
    public var channelCountMode: ChannelCountMode {
        didSet { graph.setChannelCountMode(id: id, value: channelCountMode) }
    }
    public var channelInterpretation: ChannelInterpretation {
        didSet { graph.setChannelInterpretation(id: id, value: channelInterpretation) }
    }

    let graph: AudioGraph
    let id: AudioNodeID

    init(
        context: BaseAudioContext,
        numberOfInputs: UInt32,
        numberOfOutputs: UInt32,
        options: AudioNodeOptions,
        kind: RenderNodeKind
    ) {
        self.context = context
        graph = context.graph
        self.numberOfInputs = numberOfInputs
        self.numberOfOutputs = numberOfOutputs
        channelCount = options.channelCount
        channelCountMode = options.channelCountMode
        channelInterpretation = options.channelInterpretation
        id = graph.registerNode(
            numberOfInputs: numberOfInputs,
            numberOfOutputs: numberOfOutputs,
            options: options,
            kind: kind
        )
    }

    @discardableResult
    public func connect(
        _ destinationNode: AudioNode,
        output: UInt32 = 0,
        input: UInt32 = 0
    ) throws -> AudioNode {
        guard graph === destinationNode.graph else { throw AudioGraphError.differentContext }
        guard output < numberOfOutputs else { throw AudioGraphError.invalidOutput(output) }
        guard input < destinationNode.numberOfInputs else { throw AudioGraphError.invalidInput(input) }
        graph.connect(source: self, output: output, destination: destinationNode, input: input)
        return destinationNode
    }

    public func connect(_ destinationParam: AudioParam, output: UInt32 = 0) throws {
        guard graph === destinationParam.graph else { throw AudioGraphError.differentContext }
        guard output < numberOfOutputs else { throw AudioGraphError.invalidOutput(output) }
        graph.connect(source: self, output: output, destination: destinationParam)
    }

    public func disconnect() {
        graph.disconnect(source: self)
    }

    public func disconnect(output: UInt32) throws {
        guard output < numberOfOutputs else { throw AudioGraphError.invalidOutput(output) }
        graph.disconnect(source: self, output: output)
    }

    public func disconnect(_ destinationNode: AudioNode, output: UInt32? = nil, input: UInt32? = nil) throws {
        guard graph === destinationNode.graph else { throw AudioGraphError.differentContext }
        if let output, output >= numberOfOutputs { throw AudioGraphError.invalidOutput(output) }
        if let input, input >= destinationNode.numberOfInputs { throw AudioGraphError.invalidInput(input) }
        graph.disconnect(source: self, destination: destinationNode, output: output, input: input)
    }

    public func disconnect(_ destinationParam: AudioParam, output: UInt32? = nil) throws {
        guard graph === destinationParam.graph else { throw AudioGraphError.differentContext }
        if let output, output >= numberOfOutputs { throw AudioGraphError.invalidOutput(output) }
        graph.disconnect(source: self, destination: destinationParam, output: output)
    }
}
