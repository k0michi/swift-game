struct RenderNodeConnection: Hashable, Sendable {
    let source: AudioNodeID
    let output: UInt32
    let destination: AudioNodeID
    let input: UInt32
}
