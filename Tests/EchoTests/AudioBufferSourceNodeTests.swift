import Echo
import Testing

private let sampleRate: Float = 48_000

// The first channel of what `context` renders, and its number of channels.
// getChannelData's pointer is valid only while the buffer is, so the samples
// are copied out.
@MainActor
private func rendered(_ context: OfflineAudioContext, channel: UInt32 = 0) async throws -> [Float] {
    let buffer = try await context.startRendering()
    var samples = [Float](repeating: 0, count: Int(buffer.length))
    try buffer.copyFromChannel(&samples, channelNumber: channel)
    return samples
}

// A buffer whose frame n is n, in each channel, plus 1000 times the channel.
@MainActor
private func ramp(length: UInt32, channels: UInt32 = 1, sampleRate: Float = sampleRate) throws -> AudioBuffer {
    let buffer = try AudioBuffer(options: AudioBufferOptions(numberOfChannels: channels, length: length, sampleRate: sampleRate))
    for channel in 0 ..< channels {
        try buffer.copyToChannel((0 ..< length).map { Float($0) + 1000 * Float(channel) }, channelNumber: channel)
    }
    return buffer
}

// Plays `buffer` through a source set up by `configure`, which also starts
// it.
@MainActor
private func play(
    _ buffer: AudioBuffer?,
    length: UInt32 = 256,
    configure: (OfflineAudioContext, AudioBufferSourceNode) throws -> Void
) async throws -> [Float] {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: length, sampleRate: sampleRate)
    let source = try AudioBufferSourceNode(context: context, options: AudioBufferSourceOptions(buffer: buffer))
    try source.connect(context.destination)
    try configure(context, source)
    return try await rendered(context)
}

private func isClose(_ samples: ArraySlice<Float>, _ expected: (Int) -> Float) -> Bool {
    samples.indices.allSatisfy { abs(samples[$0] - expected($0)) < 1e-3 }
}

@MainActor
@Test func bufferSourceHasTheSpecifiedDefaults() throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: sampleRate)
    let source = context.createBufferSource()
    #expect(source.buffer == nil && !source.loop && source.loopStart == 0 && source.loopEnd == 0)
    #expect(source.numberOfInputs == 0 && source.numberOfOutputs == 1)
    #expect(source.playbackRate.defaultValue == 1 && source.playbackRate.automationRate == .kRate)
    #expect(source.detune.defaultValue == 0 && source.detune.automationRate == .kRate)
    #expect(source.playbackRate.maxValue == .greatestFiniteMagnitude)
    // The rates are fixed: a change does not take.
    source.playbackRate.automationRate = .aRate
    #expect(source.playbackRate.automationRate == .kRate)
}

@MainActor
@Test func bufferSourcePlaysTheBufferOnceThenSilence() async throws {
    let samples = try await play(try ramp(length: 100)) { _, source in try source.start() }
    #expect(isClose(samples[0 ..< 100]) { Float($0) })
    #expect(samples[100...].allSatisfy { $0 == 0 })
}

@MainActor
@Test func bufferSourceStartsAtTimeFromOffsetForDuration() async throws {
    // From frame 10 of the buffer at frame 32, for 20 frames of it.
    let samples = try await play(try ramp(length: 100)) { _, source in
        try source.start(32 / Double(sampleRate), offset: 10 / Double(sampleRate), duration: 20 / Double(sampleRate))
    }
    #expect(samples[0 ..< 32].allSatisfy { $0 == 0 })
    #expect(isClose(samples[32 ..< 52]) { Float($0 - 22) })
    #expect(samples[52...].allSatisfy { $0 == 0 })
}

@MainActor
@Test func bufferSourceStopsAtTheStopTime() async throws {
    let samples = try await play(try ramp(length: 200)) { _, source in
        try source.start()
        try source.stop(50 / Double(sampleRate))
    }
    #expect(isClose(samples[0 ..< 50]) { Float($0) })
    #expect(samples[50...].allSatisfy { $0 == 0 })
}

@MainActor
@Test func bufferSourceLoopsBetweenItsPoints() async throws {
    // Frames 0 to 39, then 20 to 39 again and again.
    let samples = try await play(try ramp(length: 100), length: 128) { _, source in
        source.loop = true
        source.loopStart = 20 / Double(sampleRate)
        source.loopEnd = 40 / Double(sampleRate)
        try source.start()
    }
    #expect(isClose(samples[0 ..< 128]) { $0 < 40 ? Float($0) : Float(20 + ($0 - 40) % 20) })
}

@MainActor
@Test func bufferSourceLoopsTheWholeBufferByDefault() async throws {
    let samples = try await play(try ramp(length: 50)) { _, source in
        source.loop = true
        try source.start()
    }
    #expect(isClose(samples[0 ..< 256]) { Float($0 % 50) })
}

@MainActor
@Test func bufferSourceInterpolatesAtHalfRate() async throws {
    // Half speed: every other frame halfway between two of the buffer's.
    let samples = try await play(try ramp(length: 100)) { _, source in
        source.playbackRate.value = 0.5
        try source.start()
    }
    #expect(isClose(samples[0 ..< 190]) { Float($0) / 2 })
}

@MainActor
@Test func detuneAndBufferSampleRateSetThePlaybackSpeed() async throws {
    // An octave of detune doubles the speed; a buffer at half the context's
    // rate halves it again.
    let samples = try await play(try ramp(length: 100, sampleRate: sampleRate / 2)) { _, source in
        source.detune.value = 1200
        try source.start()
    }
    #expect(isClose(samples[0 ..< 100]) { Float($0) })
}

@MainActor
@Test func bufferSourcePlaysBackwardWithNegativeRate() async throws {
    // From the end of the buffer back to its start.
    let samples = try await play(try ramp(length: 100)) { _, source in
        source.playbackRate.value = -1
        try source.start(0, offset: 99 / Double(sampleRate))
    }
    #expect(isClose(samples[0 ..< 100]) { Float(99 - $0) })
    #expect(samples[100...].allSatisfy { $0 == 0 })
}

@MainActor
@Test func bufferSourceOutputsTheBufferChannelsThenOneOfSilence() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 2, length: 256, sampleRate: sampleRate)
    let source = try AudioBufferSourceNode(
        context: context,
        options: AudioBufferSourceOptions(buffer: try ramp(length: 64, channels: 2))
    )
    // A gain keeps the source's channels, so the destination sees them.
    let gain = context.createGain()
    try source.connect(gain).connect(context.destination)
    try source.start()
    let buffer = try await context.startRendering()
    var left = [Float](repeating: 0, count: 256)
    var right = left
    try buffer.copyFromChannel(&left, channelNumber: 0)
    try buffer.copyFromChannel(&right, channelNumber: 1)
    #expect(isClose(left[0 ..< 64]) { Float($0) } && isClose(right[0 ..< 64]) { Float($0) + 1000 })
    #expect(left[64...].allSatisfy { $0 == 0 } && right[64...].allSatisfy { $0 == 0 })
}

@MainActor
@Test func bufferSourceAcquiresTheBufferWhenStarted() async throws {
    // Changes to the buffer after the start are not heard.
    let buffer = try ramp(length: 64)
    let samples = try await play(buffer) { _, source in
        try source.start()
        try buffer.copyToChannel([Float](repeating: -1, count: 64), channelNumber: 0)
    }
    #expect(isClose(samples[0 ..< 64]) { Float($0) })
}

@MainActor
@Test func bufferIsSetOnlyOnce() throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: sampleRate)
    let source = context.createBufferSource()
    try source.setBuffer(nil)
    try source.setBuffer(try ramp(length: 8))
    #expect(throws: WebAudioError.invalidState) { try source.setBuffer(try ramp(length: 8)) }
    try source.setBuffer(nil)
    #expect(source.buffer == nil)
    #expect(throws: WebAudioError.invalidState) { try source.setBuffer(try ramp(length: 8)) }
}

@MainActor
@Test func bufferSourceErrors() throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: sampleRate)
    let source = context.createBufferSource()
    #expect(throws: WebAudioError.invalidState) { try source.stop() }
    #expect(throws: WebAudioError.rangeError) { try source.start(-1) }
    #expect(throws: WebAudioError.rangeError) { try source.start(0, offset: -1) }
    #expect(throws: WebAudioError.rangeError) { try source.start(0, offset: 0, duration: -1) }
    try source.start()
    #expect(throws: WebAudioError.invalidState) { try source.start() }
    #expect(throws: WebAudioError.rangeError) {
        try AudioBufferSourceNode(context: context, options: AudioBufferSourceOptions(playbackRate: .nan))
    }
    #expect(throws: WebAudioError.rangeError) {
        try AudioBufferSourceNode(context: context, options: AudioBufferSourceOptions(loopEnd: .infinity))
    }
}

@MainActor
@Test func sourcesCallOnendedWhenTheyEnd() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 512, sampleRate: sampleRate)
    var ended: [String] = []
    // The buffer runs out, the duration is reached, and the others stop.
    let buffer = try AudioBufferSourceNode(context: context, options: AudioBufferSourceOptions(buffer: try ramp(length: 64)))
    buffer.onended = { ended.append("buffer") }
    let duration = try AudioBufferSourceNode(
        context: context, options: AudioBufferSourceOptions(buffer: try ramp(length: 64), loop: true)
    )
    duration.onended = { ended.append("duration") }
    let oscillator = context.createOscillator()
    oscillator.onended = { ended.append("oscillator") }
    let constant = context.createConstantSource()
    constant.onended = { ended.append("constant") }
    let playing = context.createConstantSource()
    playing.onended = { ended.append("playing") }
    for source: AudioScheduledSourceNode in [buffer, duration, oscillator, constant, playing] {
        try source.connect(context.destination)
    }
    try buffer.start()
    try duration.start(0, offset: 0, duration: 100 / Double(sampleRate))
    try oscillator.start()
    try oscillator.stop(200 / Double(sampleRate))
    try constant.start()
    try constant.stop(300 / Double(sampleRate))
    try playing.start()
    _ = try await context.startRendering()
    #expect(Set(ended) == ["buffer", "duration", "oscillator", "constant"], "\(ended)")
}
