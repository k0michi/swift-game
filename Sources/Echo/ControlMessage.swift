enum ControlMessage {
    case registerNode(RenderNodeState)
    case registerParam(RenderParamState)
    case connectNodes(RenderNodeConnection)
    case connectParam(RenderParamConnection)
    case disconnectAll(source: AudioNodeID)
    case disconnectOutput(source: AudioNodeID, output: UInt32)
    case disconnectNodes(
        source: AudioNodeID,
        destination: AudioNodeID,
        output: UInt32?,
        input: UInt32?
    )
    case disconnectParam(
        source: AudioNodeID,
        destination: AudioParamID,
        output: UInt32?
    )
    case setChannelCount(id: AudioNodeID, value: UInt32)
    case setChannelCountMode(id: AudioNodeID, value: ChannelCountMode)
    case setChannelInterpretation(id: AudioNodeID, value: ChannelInterpretation)
    case setParamValue(id: AudioParamID, value: Float)
    case setAutomationRate(id: AudioParamID, value: AutomationRate)
}
