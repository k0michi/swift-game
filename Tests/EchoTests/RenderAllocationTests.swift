import Atomics
import CAllocationCounter
@testable import Echo
import Testing

// An output that never renders: the test renders the plan itself.
private final class IdleAudioBackend: AudioOutputBackend, @unchecked Sendable {
    let sampleRate: Float = 48_000
    let channelCount: UInt32 = 2

    func start(
        render: @escaping @Sendable (UnsafeMutableBufferPointer<Float>) -> Void,
        onError: @escaping @Sendable () -> Void
    ) throws {}

    func stop() throws {}
}

// Unoptimized generic code allocates where specialized code does not, so
// only an optimized build shows what the rendering thread does.
#if DEBUG
private let measuresAllocations = false
#else
private let measuresAllocations = allocation_counter_is_available()
#endif

// The rendering thread must not allocate or free, which can block, so every
// node renders from memory that the control thread prepared.
@MainActor
@Test(.enabled(if: measuresAllocations))
func renderingAPlanDoesNotAllocate() async throws {
    let context = try AudioContext(backend: IdleAudioBackend())
    let quantum = 128.0 / Double(context.sampleRate)

    let oscillator = context.createOscillator()
    oscillator.frequency.value = 220
    let filter = context.createBiquadFilter()
    filter.type = .peaking
    let shaper = context.createWaveShaper()
    try shaper.setCurve([-1, -0.5, 0, 0.5, 1])
    shaper.oversample = .`4x`
    let gain = context.createGain()
    try gain.gain.setValueAtTime(0.5, startTime: 0)
        .linearRampToValueAtTime(1, endTime: 8 * quantum)
        .exponentialRampToValueAtTime(0.25, endTime: 16 * quantum)
        .setTargetAtTime(0.75, startTime: 20 * quantum, timeConstant: 0.01)
    let panner = context.createStereoPanner()
    try panner.pan.setValueCurveAtTime([-1, 0, 1], startTime: 0, duration: 24 * quantum)
    let delay = try context.createDelay(0.1)
    delay.delayTime.value = Float(quantum / 2)
    try oscillator.connect(filter).connect(shaper).connect(gain).connect(panner).connect(delay)
    try delay.connect(context.destination)

    // A cycle, broken by its delay.
    let feedback = context.createGain()
    feedback.gain.value = 0.5
    try delay.connect(feedback).connect(delay)

    // Parameters driven by other nodes.
    let modulator = context.createConstantSource()
    modulator.offset.value = 0.1
    try modulator.connect(gain.gain)
    try modulator.connect(filter.frequency)
    try modulator.connect(oscillator.detune)

    let buffer = try context.createBuffer(numberOfChannels: 2, length: 300, sampleRate: 44_100)
    for channel in 0 ..< buffer.numberOfChannels {
        let samples = try buffer.getChannelData(channel)
        for index in samples.indices { samples[index] = Float(index) / 300 }
    }
    let bufferSource = context.createBufferSource()
    try bufferSource.setBuffer(buffer)
    bufferSource.loop = true
    try modulator.connect(bufferSource.playbackRate)
    try bufferSource.connect(context.destination)

    let track = try MediaStreamTrack(sampleRate: 44_100, channelCount: 1)
    let captured = [Float](repeating: 0.25, count: 4096)
    _ = captured.withUnsafeBufferPointer { track.appendInterleaved($0) }
    try context.createMediaStreamSource(MediaStream(tracks: [track])).connect(context.destination)

    try oscillator.start()
    try oscillator.stop(32 * quantum)
    try modulator.start()
    try bufferSource.start(0)

    let quanta = 40
    let plan = try context.graph.makeRenderPlan(destination: context.destination, frameCount: 128)
    let output = try context.createBuffer(
        numberOfChannels: UInt32(plan.destinationChannelCount),
        length: UInt32(128 * quanta),
        sampleRate: context.sampleRate
    )
    let target = try OfflineRenderTarget(buffer: output, plan: plan)

    // Once, for anything prepared on first use.
    plan.render(at: 0, into: target, offset: 0)
    #expect(countAllocations(rendering: plan, into: target, quanta: 1 ..< quanta) == 0)
    #expect(try output.getChannelData(0).contains { $0 != 0 })
    try await context.close()
}

// The control thread frees the plans the rendering thread lets go of.
@MainActor
@Test(.enabled(if: measuresAllocations))
func replacingThePlanDoesNotAllocate() async throws {
    let context = try AudioContext(backend: IdleAudioBackend())
    let source = context.createConstantSource()
    try source.start()
    let gain = context.createGain()
    try source.connect(gain).connect(context.destination)
    let queue = RenderControlQueue(
        initialPlan: try context.graph.makeRenderPlan(destination: context.destination, frameCount: 128)
    )
    let engine = try RealtimeRenderEngine(
        controlQueue: queue, sampleRate: context.sampleRate, channelCount: 2, currentFrame: ManagedAtomic(0)
    )
    let output = UnsafeMutableBufferPointer<Float>.allocate(capacity: 2 * 300)
    defer { output.deallocate() }
    engine.fill(output)

    for value in [0.25, 0.5, 0.75] as [Float] {
        gain.gain.value = value
        queue.enqueue(try context.graph.makeRenderPlan(destination: context.destination, frameCount: 128))
        #expect(countAllocations(filling: output, from: engine) == 0)
        #expect(output.last == value)
        queue.reclaimAppliedPlans()
    }
    try await context.close()
}

@inline(never)
private func countAllocations(filling output: UnsafeMutableBufferPointer<Float>, from engine: RealtimeRenderEngine) -> Int {
    allocation_counter_begin()
    engine.fill(output)
    return allocation_counter_end()
}

// Apart from the test, whose own values the optimizer may free at any point.
@inline(never)
private func countAllocations(rendering plan: AudioRenderPlan, into target: OfflineRenderTarget, quanta: Range<Int>) -> Int {
    allocation_counter_begin()
    for quantum in quanta {
        plan.render(at: UInt64(quantum * plan.frameCount), into: target, offset: quantum * plan.frameCount)
    }
    return allocation_counter_end()
}
