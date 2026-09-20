struct RenderNodeState: Sendable {
    let id: AudioNodeID
    let numberOfInputs: UInt32
    let numberOfOutputs: UInt32
    var channelCount: UInt32
    var channelCountMode: ChannelCountMode
    var channelInterpretation: ChannelInterpretation
    let processor: any RenderNodeProcessor
}
