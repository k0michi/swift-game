protocol RenderNodeProcessor: AnyObject, Sendable {
    var parameterIDs: [AudioParamID] { get }
    func outputChannelCount(
        output: Int,
        inputChannelCounts: [Int],
        node: RenderNodeState
    ) -> Int
    func apply(_ command: RenderNodeCommand)
    func process(
        context: RenderProcessContext,
        inputs: [AudioBus],
        outputs: inout [AudioBus]
    )
}

extension RenderNodeProcessor {
    var parameterIDs: [AudioParamID] { [] }
    func apply(_: RenderNodeCommand) {}
}
