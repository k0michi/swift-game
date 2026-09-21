import Atomics

@MainActor
public class BaseAudioContext {
    public let sampleRate: Float
    public let renderQuantumSize: UInt32

    public private(set) var state: AudioContextState = .suspended
    public var onstatechange: ((AudioContextState) -> Void)?

    public var currentTime: Double {
        Double(currentFrame.load(ordering: .relaxed)) / Double(sampleRate)
    }

    public private(set) lazy var destination = AudioDestinationNode(
        context: self,
        numberOfChannels: destinationChannelCount
    )

    let graph = AudioGraph()
    private let destinationChannelCount: UInt32
    let currentFrame = ManagedAtomic<UInt64>(0)

    var renderFrame: UInt64 { currentFrame.load(ordering: .relaxed) }

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

    public func createConstantSource() -> ConstantSourceNode {
        ConstantSourceNode(context: self)
    }

    func setState(_ state: AudioContextState) {
        guard self.state != state else { return }

        self.state = state
        onstatechange?(state)
    }

    func graphDidChange() {}

}
