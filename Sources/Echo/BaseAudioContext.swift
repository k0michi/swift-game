open class BaseAudioContext {
    let graph: AudioGraph
    let backend: any AudioBackend
    private let destinationChannelCount: UInt32

    public private(set) lazy var destination = AudioDestinationNode(
        context: self,
        maxChannelCount: destinationChannelCount
    )
    public private(set) lazy var listener = AudioListener(context: self)

    public var sampleRate: Float { backend.sampleRate }
    public var currentTime: Double {
        Double(graph.renderGraph.clock.renderedFrames) / Double(sampleRate)
    }
    public var state: AudioContextState { backend.state }
    public var renderQuantumSize: UInt32 { backend.renderQuantumSize }

    init(backend: any AudioBackend, destinationChannelCount: UInt32 = 2) {
        self.backend = backend
        self.destinationChannelCount = destinationChannelCount
        graph = AudioGraph(
            sampleRate: backend.sampleRate,
            renderQuantumSize: backend.renderQuantumSize
        )
    }

    public func createBuffer(numberOfChannels: UInt32, length: UInt32, sampleRate: Float) throws -> AudioBuffer {
        try AudioBuffer(options: AudioBufferOptions(
            numberOfChannels: numberOfChannels,
            length: length,
            sampleRate: sampleRate
        ))
    }

    public func createGain() -> GainNode {
        GainNode(context: self)
    }

    public func createOscillator() -> OscillatorNode {
        OscillatorNode(context: self)
    }

    public func render(into output: inout AudioBus, frameCount: Int) throws {
        _ = destination
        try graph.render(into: &output, frameCount: frameCount)
    }
}
