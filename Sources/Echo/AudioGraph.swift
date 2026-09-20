final class AudioGraph {
    let messages = ControlMessageQueue()
    let renderGraph: RenderGraph

    init(sampleRate: Float, renderQuantumSize: UInt32) {
        renderGraph = RenderGraph(sampleRate: sampleRate, renderQuantumSize: renderQuantumSize)
    }

    func registerNode(
        numberOfInputs: UInt32,
        numberOfOutputs: UInt32,
        options: AudioNodeOptions,
        kind: RenderNodeKind
    ) -> AudioNodeID {
        let id = AudioNodeID()
        messages.enqueue(.registerNode(RenderNodeState(
            id: id,
            numberOfInputs: numberOfInputs,
            numberOfOutputs: numberOfOutputs,
            channelCount: options.channelCount,
            channelCountMode: options.channelCountMode,
            channelInterpretation: options.channelInterpretation,
            kind: kind
        )))
        return id
    }

    func registerParam(
        defaultValue: Float,
        minValue: Float,
        maxValue: Float,
        automationRate: AutomationRate
    ) -> AudioParamID {
        let id = AudioParamID()
        messages.enqueue(.registerParam(RenderParamState(
            id: id,
            value: defaultValue,
            defaultValue: defaultValue,
            minValue: minValue,
            maxValue: maxValue,
            automationRate: automationRate
        )))
        return id
    }

    func connect(source: AudioNode, output: UInt32, destination: AudioNode, input: UInt32) {
        messages.enqueue(.connectNodes(RenderNodeConnection(
            source: source.id, output: output,
            destination: destination.id, input: input
        )))
    }

    func connect(source: AudioNode, output: UInt32, destination: AudioParam) {
        messages.enqueue(.connectParam(RenderParamConnection(
            source: source.id, output: output, destination: destination.id
        )))
    }

    func disconnect(source: AudioNode) {
        messages.enqueue(.disconnectAll(source: source.id))
    }

    func disconnect(source: AudioNode, output: UInt32) {
        messages.enqueue(.disconnectOutput(source: source.id, output: output))
    }

    func disconnect(source: AudioNode, destination: AudioNode, output: UInt32?, input: UInt32?) {
        messages.enqueue(.disconnectNodes(
            source: source.id, destination: destination.id, output: output, input: input
        ))
    }

    func disconnect(source: AudioNode, destination: AudioParam, output: UInt32?) {
        messages.enqueue(.disconnectParam(
            source: source.id, destination: destination.id, output: output
        ))
    }

    func setChannelCount(id: AudioNodeID, value: UInt32) {
        messages.enqueue(.setChannelCount(id: id, value: value))
    }

    func setChannelCountMode(id: AudioNodeID, value: ChannelCountMode) {
        messages.enqueue(.setChannelCountMode(id: id, value: value))
    }

    func setChannelInterpretation(id: AudioNodeID, value: ChannelInterpretation) {
        messages.enqueue(.setChannelInterpretation(id: id, value: value))
    }

    func setParamValue(id: AudioParamID, value: Float) {
        messages.enqueue(.setParamValue(id: id, value: value))
    }

    func setAutomationRate(id: AudioParamID, value: AutomationRate) {
        messages.enqueue(.setAutomationRate(id: id, value: value))
    }

    func render(into output: inout AudioBus, frameCount: Int) throws {
        messages.consume { renderGraph.apply($0) }
        try renderGraph.render(into: &output, frameCount: frameCount)
    }
}
