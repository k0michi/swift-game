// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
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

    // The node for the context's output, which the context does not keep, as
    // it keeps the context: one the caller holds is the one it gets again,
    // and a new one otherwise, for the same output.
    public var destination: AudioDestinationNode {
        if let destination = destinationHandler.node as? AudioDestinationNode { return destination }
        return AudioDestinationNode(destinationHandler)
    }
    private(set) lazy var destinationHandler = AudioDestinationHandler(
        context: self,
        numberOfChannels: destinationChannelCount
    )

    let graph = AudioGraph()
    let destinationChannelCount: UInt32
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

    public func createDelay(_ maxDelayTime: Double = 1) throws -> DelayNode {
        try DelayNode(context: self, options: DelayOptions(maxDelayTime: maxDelayTime))
    }

    public func createBufferSource() -> AudioBufferSourceNode {
        // Only invalid options throw, and none are passed.
        try! AudioBufferSourceNode(context: self)
    }

    public func createBiquadFilter() -> BiquadFilterNode {
        // Only invalid options throw, and none are passed.
        try! BiquadFilterNode(context: self)
    }

    public func createGain() -> GainNode {
        // Only invalid options throw, and none are passed.
        try! GainNode(context: self)
    }

    public func createOscillator() -> OscillatorNode {
        // Only invalid options throw, and none are passed.
        try! OscillatorNode(context: self)
    }

    public func createPeriodicWave(
        real: [Float],
        imag: [Float],
        constraints: PeriodicWaveConstraints = PeriodicWaveConstraints()
    ) throws -> PeriodicWave {
        guard real.count == imag.count else { throw WebAudioError.indexSize }
        return try PeriodicWave(context: self, options: PeriodicWaveOptions(
            real: real,
            imag: imag,
            disableNormalization: constraints.disableNormalization
        ))
    }

    public func createStereoPanner() -> StereoPannerNode {
        // Only invalid options throw, and none are passed.
        try! StereoPannerNode(context: self)
    }

    public func createWaveShaper() -> WaveShaperNode {
        // Only invalid options throw, and none are passed.
        try! WaveShaperNode(context: self)
    }

    func setState(_ state: AudioContextState) {
        guard self.state != state else { return }

        self.state = state
        // A closed context renders no more, so nothing in it can sound again.
        if state == .closed {
            graph.removeAll()
            handlers.removeAll()
        }
        onstatechange?(state)
    }

    func graphDidChange() {}

    // The handlers of the context's nodes, but its destination's, which it
    // keeps while they may sound: on each update, those the caller still
    // refers to, those that play on their own and those with a tail-time
    // that still sound, and every handler these lead to. The rest, in a
    // cycle or not, can no longer sound and go with their connections.
    private var handlers: [ObjectIdentifier: AudioHandler] = [:]

    var handlerCount: Int { handlers.count }

    func register(_ handler: AudioHandler) {
        handlers[ObjectIdentifier(handler)] = handler
    }

    // Lets go of what can no longer sound, calling onended for the sources
    // that have ended, as the rendering thread cannot.
    func updateNodeLifetimes() {
        for case let source as AudioScheduledSourceHandler in handlers.values
            where source.endedSignal.hasEnded && !source.endedIsDispatched
        {
            source.endedIsDispatched = true
            source.onended?()
        }
        let roots = handlers.values.filter { handler in
            handler.isReferenced || handler.playsOnItsOwn || handler.soundingSignal?.isSounding == true
        }
        var kept: [ObjectIdentifier: AudioHandler] = [:]
        for handler in roots + graph.handlers(downstreamOf: roots) {
            kept[ObjectIdentifier(handler)] = handler
        }
        let gone = Set(handlers.keys).subtracting(kept.keys)
        guard !gone.isEmpty else { return }
        handlers = kept.filter { $0.value !== destinationHandler }
        graph.remove(gone)
        graphDidChange()
    }
}
#endif
