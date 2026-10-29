#if os(Emscripten)
@MainActor
public class BaseAudioContext {
    public let sampleRate: Float
    public let renderQuantumSize: UInt32

    public var state: AudioContextState {
        AudioContextState(rawValue: object.string("state")) ?? .suspended
    }
    public var onstatechange: ((AudioContextState) -> Void)?

    public var currentTime: Double {
        object.number("currentTime")
    }

    public private(set) lazy var destination = AudioDestinationNode(
        context: self,
        object: object.object("destination")!
    )

    let object: JSObjectReference

    init(object: JSObjectReference) {
        self.object = object
        sampleRate = Float(object.number("sampleRate"))
        // Browsers without renderSizeHint render 128 frames at a time.
        let renderQuantumSize = object.number("renderQuantumSize")
        self.renderQuantumSize = renderQuantumSize.isFinite && renderQuantumSize > 0 ? UInt32(renderQuantumSize) : 128
        object.setListener("statechange", { context in
            MainActor.assumeIsolated {
                let context = Unmanaged<BaseAudioContext>.fromOpaque(context!).takeUnretainedValue()
                context.onstatechange?(context.state)
            }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    isolated deinit {
        object.setListener("statechange", nil, nil)
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

    public func createDelay(_ maxDelayTime: Double = 1) throws -> DelayNode {
        try DelayNode(context: self, options: DelayOptions(maxDelayTime: maxDelayTime))
    }

    public func createGain() -> GainNode {
        // Only invalid options throw, and none are passed.
        try! GainNode(context: self)
    }

    public func createWaveShaper() -> WaveShaperNode {
        // Only invalid options throw, and none are passed.
        try! WaveShaperNode(context: self)
    }
}
#endif
