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

    // A stand-in for the context's output, which the context does not keep:
    // once nothing does, the next one is new, with the same settings.
    public var destination: AudioDestinationNode {
        if let destination = currentDestination { return destination }
        let destination = AudioDestinationNode(context: self, numberOfChannels: destinationChannelCount)
        currentDestination = destination
        return destination
    }
    private weak var currentDestination: AudioDestinationNode?
    // The destination's settings, which outlive its nodes.
    lazy var destinationSettings = (
        channelCount: destinationChannelCount,
        channelCountMode: ChannelCountMode.explicit,
        channelInterpretation: ChannelInterpretation.speakers
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
        onstatechange?(state)
    }

    func graphDidChange() {}

    // The context keeps the nodes that may sound. Connecting or starting a
    // node keeps it, and each update keeps only what the roots lead to: the
    // kept nodes that something besides the context refers to (the caller,
    // or the context as a playing source or a node that plays on its own),
    // and those with a tail-time that still sound. Connections between nodes
    // keep neither end, so a node that cannot sound again, in a cycle or not,
    // goes, and its connections with it.
    private var playingSources: [AudioScheduledSourceNode] = []
    private var keptNodes: [AudioNode] = []
    private var heldNodes: [ObjectIdentifier: AudioNode] = [:]

    var heldNodeCount: Int { heldNodes.count }

    func sourceDidStart(_ source: AudioScheduledSourceNode) {
        playingSources.append(source)
        hold(source)
    }

    // A node that plays on its own, whoever keeps it.
    func keep(_ node: AudioNode) {
        keptNodes.append(node)
    }

    // Keeps a node until the next update at least, so that nodes made and
    // connected in one place stay until it decides.
    func hold(_ node: AudioNode) {
        guard !(node is AudioDestinationNode) else { return }
        heldNodes[ObjectIdentifier(node)] = node
    }

    // Lets go of what can no longer sound, calling onended for the sources
    // that have ended, as the rendering thread cannot.
    func updateNodeLifetimes() {
        callOnended()
        var nodes = Array(heldNodes.values)
        heldNodes.removeAll()
        var roots: [AudioNode] = []
        for index in nodes.indices {
            // Referred to only from here: by no one else.
            let isReferredToElsewhere = !isKnownUniquelyReferenced(&nodes[index])
            if isReferredToElsewhere || nodes[index].soundingSignal?.isSounding == true {
                roots.append(nodes[index])
            }
        }
        for node in roots + graph.nodes(downstreamOf: roots) {
            heldNodes[ObjectIdentifier(node)] = node
        }
        // What is not kept goes here, with the last reference to it.
        nodes.removeAll()
        if graph.removeDeadConnections() {
            graphDidChange()
        }
    }

    // Lets go of the sources that have ended, calling their onended.
    private func callOnended() {
        let ended = playingSources.filter(\.endedSignal.hasEnded)
        playingSources.removeAll(where: \.endedSignal.hasEnded)
        for source in ended {
            source.onended?()
        }
    }
}
#endif
