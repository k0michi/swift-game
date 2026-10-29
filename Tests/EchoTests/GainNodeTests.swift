import Echo
import Testing

// The first channel of what `context` renders. getChannelData's pointer is
// valid only while the buffer is, so the samples are copied out.
@MainActor
private func rendered(_ context: OfflineAudioContext) async throws -> [Float] {
    let buffer = try await context.startRendering()
    var samples = [Float](repeating: 0, count: Int(buffer.length))
    try buffer.copyFromChannel(&samples, channelNumber: 0)
    return samples
}

// Renders a constant 1 through a GainNode set up by `configure`.
@MainActor
private func gained(length: UInt32 = 128, configure: (OfflineAudioContext, GainNode) throws -> Void) async throws
    -> [Float]
{
    let context = try OfflineAudioContext(numberOfChannels: 1, length: length, sampleRate: 48_000)
    let source = context.createConstantSource()
    let gain = context.createGain()
    try configure(context, gain)
    try source.connect(gain).connect(context.destination)
    try source.start()
    return try await rendered(context)
}

@MainActor
@Test func gainHasTheSpecifiedDefaults() throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    let gain = context.createGain()
    #expect(gain.numberOfInputs == 1 && gain.numberOfOutputs == 1)
    #expect(gain.channelCount == 2 && gain.channelCountMode == .max && gain.channelInterpretation == .speakers)
    #expect(gain.gain.defaultValue == 1 && gain.gain.value == 1)
    #expect(gain.gain.minValue == -.greatestFiniteMagnitude && gain.gain.maxValue == .greatestFiniteMagnitude)
    #expect(gain.gain.automationRate == .aRate)
}

@MainActor
@Test func gainMultipliesTheInput() async throws {
    let samples = try await gained { _, gain in gain.gain.value = -0.25 }
    #expect(samples.allSatisfy { $0 == -0.25 })
}

@MainActor
@Test func gainFromOptions() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    let source = context.createConstantSource()
    source.offset.value = 0.5
    let gain = try GainNode(context: context, options: GainOptions(channelCount: 1, gain: 3))
    #expect(gain.gain.value == 3 && gain.channelCount == 1)
    try source.connect(gain).connect(context.destination)
    try source.start()
    let samples = try await rendered(context)
    #expect(samples.allSatisfy { $0 == 1.5 })
}

@MainActor
@Test func gainFollowsItsAutomationEachFrame() async throws {
    // a-rate: a ramp from 0 to 1 over the first 128 frames.
    let samples = try await gained(length: 256) { _, gain in
        try gain.gain.setValueAtTime(0, startTime: 0)
        try gain.gain.linearRampToValueAtTime(1, endTime: 128 / 48_000)
    }
    for frame in [0, 32, 64, 96] {
        #expect(abs(samples[frame] - Float(frame) / 128) < 1e-5, "\(frame): \(samples[frame])")
    }
    #expect(samples[128...].allSatisfy { $0 == 1 })
}

@MainActor
@Test func kRateGainHoldsAcrossTheQuantum() async throws {
    let samples = try await gained(length: 256) { _, gain in
        gain.gain.automationRate = .kRate
        try gain.gain.setValueAtTime(0, startTime: 0)
        try gain.gain.linearRampToValueAtTime(1, endTime: 256 / 48_000)
    }
    // The value at each quantum's first frame.
    #expect(samples[0 ..< 128].allSatisfy { $0 == 0 })
    #expect(samples[128 ..< 256].allSatisfy { abs($0 - 0.5) < 1e-5 })
}

@MainActor
@Test func gainAddsWhatIsConnectedToIt() async throws {
    let samples = try await gained { context, gain in
        gain.gain.value = 0.25
        let modulation = context.createConstantSource()
        modulation.offset.value = 0.5
        try modulation.connect(gain.gain)
        try modulation.start()
    }
    #expect(samples.allSatisfy { $0 == 0.75 })
}

@MainActor
@Test func gainOptionsAreChecked() throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    #expect(throws: WebAudioError.rangeError) {
        try GainNode(context: context, options: GainOptions(gain: .nan))
    }
    #expect(throws: WebAudioError.rangeError) {
        try GainNode(context: context, options: GainOptions(gain: .infinity))
    }
    #expect(throws: WebAudioError.notSupported) {
        try GainNode(context: context, options: GainOptions(channelCount: 0))
    }
}
