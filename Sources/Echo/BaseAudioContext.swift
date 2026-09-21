@MainActor
public class BaseAudioContext {
    public let sampleRate: Float
    public let renderQuantumSize: UInt32

    public private(set) var state: AudioContextState = .suspended
    public var onstatechange: ((AudioContextState) -> Void)?

    public var currentTime: Double {
        Double(currentFrame) / Double(sampleRate)
    }

    public private(set) lazy var destination = AudioDestinationNode(
        context: self,
        numberOfChannels: destinationChannelCount
    )

    let graph = AudioGraph()
    private let destinationChannelCount: UInt32
    private var currentFrame: UInt64 = 0

    init(sampleRate: Float, renderQuantumSize: UInt32, destinationChannelCount: UInt32) {
        self.sampleRate = sampleRate
        self.renderQuantumSize = renderQuantumSize
        self.destinationChannelCount = destinationChannelCount
    }

    public func createBuffer(
        numberOfChannels: UInt32,
        length: UInt32,
        sampleRate: Float
    ) throws -> AudioBuffer {
        try AudioBuffer(options: AudioBufferOptions(
            numberOfChannels: numberOfChannels,
            length: length,
            sampleRate: sampleRate
        ))
    }

    func setState(_ state: AudioContextState) {
        guard self.state != state else { return }

        self.state = state
        onstatechange?(state)
    }

    func advance(by frameCount: UInt32) {
        currentFrame += UInt64(frameCount)
    }
}
