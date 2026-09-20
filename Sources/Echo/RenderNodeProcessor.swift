protocol RenderNodeProcessor: AnyObject, Sendable {
    var parameterIDs: [AudioParamID] { get }
    func outputChannelCount(inputChannelCount: Int, node: RenderNodeState) -> Int
    func apply(_ command: RenderNodeCommand)
    func process(
        context: RenderProcessContext,
        input: AudioBus,
        output: inout AudioBus
    )
}

extension RenderNodeProcessor {
    var parameterIDs: [AudioParamID] { [] }
    func apply(_: RenderNodeCommand) {}
}
