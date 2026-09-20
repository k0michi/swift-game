struct RenderParamConnection: Hashable, Sendable {
    let source: AudioNodeID
    let output: UInt32
    let destination: AudioParamID
}
