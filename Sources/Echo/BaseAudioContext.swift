open class BaseAudioContext {
    let graph = AudioGraph()
    let backend: any AudioBackend

    public private(set) lazy var destination = AudioDestinationNode(context: self)
    public private(set) lazy var listener = AudioListener(context: self)

    public var sampleRate: Float { backend.sampleRate }
    public var currentTime: Double { backend.currentTime }
    public var state: AudioContextState { backend.state }
    public var renderQuantumSize: UInt32 { backend.renderQuantumSize }

    init(backend: any AudioBackend) {
        self.backend = backend
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
}
