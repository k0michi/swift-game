@testable import Echo
import Testing

private let sampleRate: Float = 48_000

// A one-shot voice, as the game makes for each sound: a buffer of `length`
// frames of `value`, through a gain and a panner, with nothing kept.
@MainActor
private func playVoice(on context: OfflineAudioContext, at frame: Int, length: UInt32 = 64, value: Float = 1) throws {
    let buffer = try AudioBuffer(options: AudioBufferOptions(numberOfChannels: 1, length: length, sampleRate: sampleRate))
    try buffer.copyToChannel([Float](repeating: value, count: Int(length)), channelNumber: 0)
    let source = try AudioBufferSourceNode(context: context, options: AudioBufferSourceOptions(buffer: buffer))
    let gain = try GainNode(context: context, options: GainOptions(gain: 0.5))
    let panner = context.createStereoPanner()
    try source.connect(gain).connect(panner).connect(context.destination)
    try source.start(Double(frame) / Double(sampleRate))
}

// Renders `quanta` render quanta one at a time, so that the context lets go
// of what has ended after each, with `atQuantum` run before each. Returns
// the first channel and the graph's connection count before each quantum.
@MainActor
private func renderByQuantum(
    _ context: OfflineAudioContext,
    quanta: Int,
    atQuantum: (Int) throws -> Void = { _ in }
) async throws -> (samples: [Float], counts: [Int]) {
    var samples: [Float] = []
    var counts: [Int] = []
    for quantum in 0 ..< quanta {
        try atQuantum(quantum)
        counts.append(context.graph.connectionCount)
        let buffer = try await context.startRendering(chunkSize: 128)
        var chunk = [Float](repeating: 0, count: Int(buffer.length))
        try buffer.copyFromChannel(&chunk, channelNumber: 0)
        samples += chunk
    }
    return (samples, counts)
}

@MainActor
@Test func endedVoicesLeaveTheGraph() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128 * 40, sampleRate: sampleRate)
    // A voice every other quantum, each over within it.
    let (rendered, counts) = try await renderByQuantum(context, quanta: 40) { quantum in
        if quantum.isMultiple(of: 2), quantum < 30 {
            try playVoice(on: context, at: quantum * 128 + 16)
        }
    }
    // A voice is three connections while it plays and none once it ends.
    #expect(counts.max()! == 3, "\(counts)")
    #expect(counts.suffix(10).allSatisfy { $0 == 0 }, "\(counts)")
    #expect(context.graph.connectionCount == 0)

    // Each voice still played whole: half of 1, through the panner's
    // center, cos π/4.
    let level = Float(0.5 * 0.70710677)
    for quantum in stride(from: 0, to: 30, by: 2) {
        let start = quantum * 128 + 16
        #expect(rendered[start ..< start + 64].allSatisfy { abs($0 - level) < 1e-5 }, "voice at \(quantum)")
        #expect(rendered[start + 64 ..< start + 112].allSatisfy { $0 == 0 }, "after the voice at \(quantum)")
    }
}

@MainActor
@Test func nodesTheCallerKeepsStayConnected() async throws {
    // A shared gain the caller keeps, fed by voices that end; a later voice
    // through it still plays.
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128 * 8, sampleRate: sampleRate)
    let shared = context.createGain()
    try shared.connect(context.destination)
    func voice(at frame: Int) throws {
        let source = context.createConstantSource()
        try source.connect(shared)
        try source.start(Double(frame) / Double(sampleRate))
        try source.stop(Double(frame + 64) / Double(sampleRate))
    }
    let (rendered, counts) = try await renderByQuantum(context, quanta: 8) { quantum in
        if quantum == 0 || quantum == 4 {
            try voice(at: quantum * 128)
        }
    }
    #expect(rendered[0 ..< 64].allSatisfy { $0 == 1 } && rendered[64 ..< 512].allSatisfy { $0 == 0 })
    #expect(rendered[512 ..< 576].allSatisfy { $0 == 1 } && rendered[576...].allSatisfy { $0 == 0 })
    // The shared gain's connection stays; each voice's goes once it ends.
    #expect(counts == [2, 1, 1, 1, 2, 1, 1, 1], "\(counts)")
    withExtendedLifetime(shared) {}
}

// An impulse into a resonant lowpass, which the caller keeps only when
// `keepFilter` is set.
@MainActor
private func ringFilter(on context: OfflineAudioContext, keepFilter: Bool) throws -> BiquadFilterNode? {
    let impulse = try AudioBuffer(options: AudioBufferOptions(numberOfChannels: 1, length: 1, sampleRate: sampleRate))
    try impulse.copyToChannel([1], channelNumber: 0)
    let source = try AudioBufferSourceNode(context: context, options: AudioBufferSourceOptions(buffer: impulse))
    let filter = try BiquadFilterNode(context: context, options: BiquadFilterOptions(Q: 20, frequency: 2000))
    try source.connect(filter).connect(context.destination)
    try source.start()
    return keepFilter ? filter : nil
}

@MainActor
@Test func aFilterRingsOnAfterItsSourceIsGone() async throws {
    // Once the impulse's source has gone, the filter, which nothing else
    // keeps, rings on as it would have, and goes only once silent.
    let released = try OfflineAudioContext(numberOfChannels: 1, length: 128 * 64, sampleRate: sampleRate)
    _ = try ringFilter(on: released, keepFilter: false)
    let (releasedSamples, counts) = try await renderByQuantum(released, quanta: 64)

    let kept = try OfflineAudioContext(numberOfChannels: 1, length: 128 * 64, sampleRate: sampleRate)
    let filter = try ringFilter(on: kept, keepFilter: true)
    let (keptSamples, _) = try await renderByQuantum(kept, quanta: 64)
    withExtendedLifetime(filter) {}

    // The source's connection goes after the first quantum; the filter's,
    // once a quantum of it is silent.
    #expect(counts[0] == 2 && counts[1] == 1, "\(counts)")
    let silentFrom = try #require(counts.firstIndex(of: 0), "\(counts)")
    #expect(silentFrom > 2, "\(counts)")
    // Until then it rang as if kept; after, both are below 2^-126, where the
    // kept one goes on in denormals.
    let releasedAt = (silentFrom - 1) * 128
    #expect(releasedSamples[..<releasedAt] == keptSamples[..<releasedAt])
    #expect(releasedSamples[0 ..< 128].contains { abs($0) > 0.01 })
    #expect(releasedSamples[releasedAt...].allSatisfy { abs($0) < .leastNormalMagnitude })
    #expect(keptSamples[releasedAt...].allSatisfy { abs($0) < .leastNormalMagnitude })
}


// An output that renders only when pulled.
private final class PulledAudioBackend: AudioOutputBackend, @unchecked Sendable {
    let sampleRate: Float = 48_000
    let channelCount: UInt32 = 1
    private var render: (@Sendable (UnsafeMutableBufferPointer<Float>) -> Void)?

    func start(
        render: @escaping @Sendable (UnsafeMutableBufferPointer<Float>) -> Void,
        onError: @escaping @Sendable () -> Void
    ) throws {
        self.render = render
    }

    func stop() throws {
        render = nil
    }

    func pull(frames: Int) -> [Float] {
        var samples = [Float](repeating: 0, count: frames)
        samples.withUnsafeMutableBufferPointer { render?($0) }
        return samples
    }
}

@MainActor
@Test func aRunningContextLetsGoOfEndedVoices() async throws {
    let backend = PulledAudioBackend()
    let context = try AudioContext(backend: backend)
    try await context.resume()
    var ended = false
    func voice() throws {
        let oscillator = context.createOscillator()
        let gain = context.createGain()
        try oscillator.connect(gain).connect(context.destination)
        oscillator.onended = { ended = true }
        try oscillator.start()
        try oscillator.stop(64 / Double(sampleRate))
    }
    try voice()
    #expect(context.graph.connectionCount == 2)
    _ = backend.pull(frames: 256)
    // The context checks every 10 ms.
    for _ in 0 ..< 200 where !(ended && context.graph.connectionCount == 0) {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(ended)
    #expect(context.graph.connectionCount == 0)
    try await context.close()
}

// An impulse into an echo, a delay feeding itself back through a gain of
// one half, with no node kept. Returns their handlers.
@MainActor
private func echo(on context: OfflineAudioContext) throws -> (delay: AudioHandler, gain: AudioHandler) {
    let impulse = try AudioBuffer(options: AudioBufferOptions(numberOfChannels: 1, length: 1, sampleRate: sampleRate))
    try impulse.copyToChannel([1], channelNumber: 0)
    let source = try AudioBufferSourceNode(context: context, options: AudioBufferSourceOptions(buffer: impulse))
    // A short longest delay, which is how long the loop's tail can be.
    let delay = try DelayNode(
        context: context,
        options: DelayOptions(maxDelayTime: 256 / Double(sampleRate), delayTime: 128 / Double(sampleRate))
    )
    let gain = try GainNode(context: context, options: GainOptions(gain: 0.5))
    try source.connect(delay).connect(gain).connect(delay)
    try delay.connect(context.destination)
    try source.start()
    return (delay.handler, gain.handler)
}

@MainActor
@Test func aFeedbackLoopGoesOnceSilent() async throws {
    // The loop keeps neither of its nodes: they go once the echoes fade
    // below 2^-126, though they still lead to each other.
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128 * 300, sampleRate: sampleRate)
    // The handlers, which the context keeps while they may sound.
    weak var delay: AudioHandler?
    weak var gain: AudioHandler?
    (delay, gain) = try echo(on: context)
    let (rendered, counts) = try await renderByQuantum(context, quanta: 300)
    // Echoes a quantum apart, each half the last.
    #expect(abs(rendered[128] - 1) < 1e-6 && abs(rendered[256] - 0.5) < 1e-6 && abs(rendered[384] - 0.25) < 1e-6)
    #expect(counts[1] == 3, "\(counts)")
    #expect(counts.last == 0, "\(counts)")
    #expect(delay == nil && gain == nil)
}

@MainActor
@Test func theDestinationIsAStandIn() async throws {
    let backend = PulledAudioBackend()
    let context = try AudioContext(backend: backend)
    weak var first: AudioDestinationNode?
    func configure() throws {
        let destination = context.destination
        first = destination
        destination.setChannelInterpretation(.discrete)
        try destination.setChannelCountMode(.clampedMax)
    }
    try configure()
    // Nothing keeps it, and the next is another with the same settings.
    #expect(first == nil)
    let next = context.destination
    #expect(next.channelInterpretation == .discrete && next.channelCountMode == .clampedMax)
    #expect(next.channelCount == 1 && next.maxChannelCount == 1)
    try await context.close()
}

@MainActor
@Test func aSourceNotYetStartedKeepsTheNodesAfterIt() async throws {
    // The caller keeps only the source; the gain after it stays until the
    // source starts, a quantum later, and plays.
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128 * 4, sampleRate: sampleRate)
    let source = context.createConstantSource()
    func connect() throws {
        let gain = try GainNode(context: context, options: GainOptions(gain: 0.5))
        try source.connect(gain).connect(context.destination)
    }
    try connect()
    let (rendered, counts) = try await renderByQuantum(context, quanta: 4) { quantum in
        if quantum == 2 {
            try source.start()
        }
    }
    #expect(counts == [2, 2, 2, 2], "\(counts)")
    #expect(rendered[..<256].allSatisfy { $0 == 0 } && rendered[256...].allSatisfy { $0 == 0.5 })
}

@MainActor
@Test func aNodeTheCallerKeepsKeepsTheNodesAfterIt() async throws {
    // A gain the caller keeps, with nothing playing into it yet, keeps the
    // panner after it, which nothing else keeps; a source connected to the
    // gain later plays through both.
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128 * 4, sampleRate: sampleRate)
    let gain = try GainNode(context: context, options: GainOptions(gain: 0.5))
    weak var panner: AudioHandler?
    func connect() throws {
        let made = context.createStereoPanner()
        try gain.connect(made).connect(context.destination)
        panner = made.handler
    }
    try connect()
    var pannerStayed = false
    let (rendered, counts) = try await renderByQuantum(context, quanta: 4) { quantum in
        if quantum == 2 {
            let source = context.createConstantSource()
            try source.connect(gain)
            try source.start()
        }
        pannerStayed = panner != nil
    }
    // Until the context closes, once rendered, and lets go of everything.
    #expect(pannerStayed && panner == nil)
    #expect(counts == [2, 2, 3, 3], "\(counts)")
    // Half of 1 through the panner's center, cos π/4.
    #expect(rendered[..<256].allSatisfy { $0 == 0 })
    #expect(rendered[256...].allSatisfy { abs($0 - 0.5 * 0.70710677) < 1e-6 })
    withExtendedLifetime(gain) {}
}

@MainActor
@Test func nodesGoWithTheLastNodeThatKeptThem() async throws {
    // Once the caller lets go of the gain, it and the panner after it go.
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128 * 3, sampleRate: sampleRate)
    var gain: GainNode? = context.createGain()
    weak var panner: AudioHandler?
    func connect() throws {
        let made = context.createStereoPanner()
        try gain!.connect(made).connect(context.destination)
        panner = made.handler
    }
    try connect()
    let (_, counts) = try await renderByQuantum(context, quanta: 3) { quantum in
        if quantum == 1 {
            gain = nil
        }
    }
    #expect(counts == [2, 2, 0], "\(counts)")
    #expect(panner == nil)
}

@MainActor
@Test func aFinishedOfflineContextGoesWithItsNodes() async throws {
    // A loop that never ends, through a gain, keeps the context while it
    // renders; once rendered, the context is closed and lets go of them all.
    weak var weakContext: OfflineAudioContext?
    weak var weakSource: AudioHandler?
    weak var weakGain: AudioHandler?
    func render() async throws {
        let context = try OfflineAudioContext(numberOfChannels: 1, length: 256, sampleRate: sampleRate)
        let buffer = try AudioBuffer(options: AudioBufferOptions(numberOfChannels: 1, length: 64, sampleRate: sampleRate))
        let source = try AudioBufferSourceNode(context: context, options: AudioBufferSourceOptions(buffer: buffer, loop: true))
        let gain = context.createGain()
        try source.connect(gain).connect(context.destination)
        try source.start()
        (weakContext, weakSource, weakGain) = (context, source.handler, gain.handler)
        _ = try await context.startRendering()
        #expect(context.state == .closed)
    }
    try await render()
    #expect(weakContext == nil && weakSource == nil && weakGain == nil)
}

@MainActor
@Test func aClosedContextGoesWithItsNodes() async throws {
    weak var weakContext: AudioContext?
    weak var weakSource: AudioHandler?
    func play() async throws {
        let context = try AudioContext(backend: PulledAudioBackend())
        try await context.resume()
        let source = context.createConstantSource()
        try source.connect(context.destination)
        try source.start()
        (weakContext, weakSource) = (context, source.handler)
    }
    try await play()
    // Running, the context keeps itself, and its source's handler.
    #expect(weakContext != nil && weakSource != nil)
    try await weakContext?.close()
    #expect(weakContext == nil && weakSource == nil)
}

@MainActor
@Test func aParameterTheCallerKeepsKeepsItsNode() async throws {
    // Holding only a gain's parameter keeps the gain, and what it leads to,
    // as it does in the browser; letting go of it lets the gain go.
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128 * 4, sampleRate: sampleRate)
    var parameter: AudioParam?
    weak var gain: AudioHandler?
    func connect() throws {
        let made = context.createGain()
        try made.connect(context.destination)
        (parameter, gain) = (made.gain, made.handler)
    }
    try connect()
    let (_, counts) = try await renderByQuantum(context, quanta: 4) { quantum in
        if quantum == 2 {
            parameter = nil
        }
    }
    #expect(counts == [1, 1, 1, 0], "\(counts)")
    #expect(gain == nil)
}

@MainActor
@Test func aRunningContextKeepsItselfUntilClosed() async throws {
    // A running context plays on with nothing else keeping it, as in the
    // browser, and goes once closed.
    let backend = PulledAudioBackend()
    weak var weakContext: AudioContext?
    func play() async throws {
        let context = try AudioContext(backend: backend)
        let source = context.createConstantSource()
        try source.connect(context.destination)
        try source.start()
        try await context.resume()
        weakContext = context
    }
    try await play()
    #expect(weakContext != nil)
    #expect(backend.pull(frames: 128).allSatisfy { $0 == 1 })
    try await weakContext?.close()
    #expect(weakContext == nil)
}

@MainActor
@Test func aTrackPlaysOnItsOwnWhileLive() async throws {
    // A media stream source nothing keeps stays while its track is live,
    // and goes once the track ends.
    let backend = PulledAudioBackend()
    let context = try AudioContext(backend: backend)
    let track = try MediaStreamTrack(id: "a", sampleRate: sampleRate, channelCount: 1)
    weak var weakSource: AudioHandler?
    func connect() throws {
        let source = try context.createMediaStreamSource(MediaStream(tracks: [track]))
        try source.connect(context.destination)
        weakSource = source.handler
    }
    try connect()
    context.updateNodeLifetimes()
    #expect(weakSource != nil && context.graph.connectionCount == 1)
    track.stop()
    context.updateNodeLifetimes()
    #expect(weakSource == nil && context.graph.connectionCount == 0)
    try await context.close()
}
