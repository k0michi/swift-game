import Echo
import Foundation
import Testing

private let sampleRate: Float = 48_000

// The first channel of what `context` renders. getChannelData's pointer is
// valid only while the buffer is, so the samples are copied out.
@MainActor
private func rendered(_ context: OfflineAudioContext) async throws -> [Float] {
    let buffer = try await context.startRendering()
    var samples = [Float](repeating: 0, count: Int(buffer.length))
    try buffer.copyFromChannel(&samples, channelNumber: 0)
    return samples
}

// Renders an oscillator set up by `configure`, started at 0 unless it starts
// itself.
@MainActor
private func oscillate(
    length: UInt32 = 512,
    configure: (OfflineAudioContext, OscillatorNode) throws -> Void
) async throws -> [Float] {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: length, sampleRate: sampleRate)
    let oscillator = context.createOscillator()
    try configure(context, oscillator)
    try oscillator.connect(context.destination)
    try? oscillator.start()
    return try await rendered(context)
}

private func sine(_ frequency: Double, frame: Double, phase: Double = 0) -> Float {
    Float(sin(2 * .pi * (frequency * frame / Double(sampleRate) + phase)))
}

private func largestDifference(_ samples: [Float], _ expected: (Int) -> Float, in range: Range<Int>) -> Float {
    range.map { abs(samples[$0] - expected($0)) }.max()!
}

@MainActor
@Test func oscillatorHasTheSpecifiedDefaults() throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: sampleRate)
    let oscillator = context.createOscillator()
    #expect(oscillator.type == .sine)
    #expect(oscillator.numberOfInputs == 0 && oscillator.numberOfOutputs == 1)
    #expect(oscillator.channelCount == 2 && oscillator.channelCountMode == .max)
    #expect(oscillator.frequency.defaultValue == 440 && oscillator.frequency.automationRate == .aRate)
    #expect(oscillator.frequency.minValue == -24_000 && oscillator.frequency.maxValue == 24_000)
    #expect(oscillator.detune.defaultValue == 0 && oscillator.detune.automationRate == .aRate)
    #expect(abs(oscillator.detune.maxValue - 153_600) < 1 && oscillator.detune.minValue == -oscillator.detune.maxValue)
}

@MainActor
@Test func sineStartsAtZeroPhase() async throws {
    let samples = try await oscillate { _, oscillator in oscillator.frequency.value = 375 }
    #expect(largestDifference(samples, { sine(375, frame: Double($0)) }, in: 0 ..< 512) < 1e-4)
}

@MainActor
@Test func detuneShiftsTheFrequencyInCents() async throws {
    // An octave up from 375 Hz.
    let samples = try await oscillate { _, oscillator in
        oscillator.frequency.value = 375
        oscillator.detune.value = 1200
    }
    #expect(largestDifference(samples, { sine(750, frame: Double($0)) }, in: 0 ..< 512) < 1e-4)
}

@MainActor
@Test func frequencyAndDetuneAreClampedOnlyTogether() async throws {
    // 30 kHz is beyond the Nyquist frequency alone, but an octave down it is
    // 15 kHz, which the oscillator plays.
    let samples = try await oscillate { _, oscillator in
        oscillator.frequency.value = 30_000
        oscillator.detune.value = -1200
    }
    #expect(largestDifference(samples, { sine(15_000, frame: Double($0)) }, in: 0 ..< 512) < 1e-3)
}

@MainActor
@Test func startAndStopAtExactTimes() async throws {
    // Started half a frame after frame 64, so frame 65 is half a frame in.
    let samples = try await oscillate { _, oscillator in
        oscillator.frequency.value = 375
        try oscillator.start(64.5 / Double(sampleRate))
        try oscillator.stop(192 / Double(sampleRate))
    }
    #expect(samples[0 ... 64].allSatisfy { $0 == 0 })
    #expect(largestDifference(samples, { sine(375, frame: Double($0) - 64.5) }, in: 65 ..< 192) < 1e-4)
    #expect(samples[192...].allSatisfy { $0 == 0 })
}

@MainActor
@Test func stopBeforeStartKeepsItSilent() async throws {
    let samples = try await oscillate { _, oscillator in
        try oscillator.start(256 / Double(sampleRate))
        try oscillator.stop(128 / Double(sampleRate))
    }
    #expect(samples.allSatisfy { $0 == 0 })
}

@MainActor
@Test(arguments: [OscillatorType.square, .sawtooth, .triangle])
func builtInWaveformsAreOddWithAPositiveSlopeAndNormalized(type: OscillatorType) async throws {
    // 93.75 Hz: a period of 512 frames, so frame n and frame 512 - n are
    // opposite.
    let samples = try await oscillate(length: 1024) { _, oscillator in
        try oscillator.setType(type)
        oscillator.frequency.value = 93.75
    }
    #expect(abs(samples[0]) < 1e-3, "\(samples[0])")
    #expect(samples[1] > 0, "\(samples[1])")
    #expect((1 ..< 256).allSatisfy { abs(samples[$0] + samples[512 - $0]) < 1e-3 })
    let peak = samples.map(abs).max()!
    #expect(peak <= 1.001 && peak > 0.95, "\(peak)")
}

@MainActor
@Test func squareIsPositiveForItsFirstHalf() async throws {
    let samples = try await oscillate(length: 512) { _, oscillator in
        try oscillator.setType(.square)
        oscillator.frequency.value = 93.75
    }
    #expect(samples[8 ..< 248].allSatisfy { $0 > 0.7 })
    #expect(samples[264 ..< 504].allSatisfy { $0 < -0.7 })
}

@MainActor
@Test func periodicWaveMakesACustomWaveform() async throws {
    // The second harmonic alone, normalized to a peak of 1.
    let second = try await oscillate { context, oscillator in
        oscillator.frequency.value = 375
        oscillator.setPeriodicWave(try context.createPeriodicWave(real: [0, 0, 0], imag: [0, 0, 0.25]))
        #expect(oscillator.type == .custom)
    }
    #expect(largestDifference(second, { sine(750, frame: Double($0)) }, in: 0 ..< 512) < 1e-4)

    // A cosine at half amplitude without normalization, and no DC term
    // however real[0] is set.
    let cosine = try await oscillate { context, oscillator in
        oscillator.frequency.value = 375
        oscillator.setPeriodicWave(try PeriodicWave(
            context: context,
            options: PeriodicWaveOptions(real: [5, 0.5], disableNormalization: true)
        ))
    }
    #expect(largestDifference(cosine, { 0.5 * sine(375, frame: Double($0), phase: 0.25) }, in: 0 ..< 512) < 1e-4)

    // Neither array makes a sine.
    let plain = try await oscillate { context, oscillator in
        oscillator.frequency.value = 375
        oscillator.setPeriodicWave(try PeriodicWave(context: context))
    }
    #expect(largestDifference(plain, { sine(375, frame: Double($0)) }, in: 0 ..< 512) < 1e-4)
}

@MainActor
@Test func periodicWaveFromOptionsOverridesType() async throws {
    let samples = try await oscillate { context, oscillator in
        let wave = try PeriodicWave(context: context, options: PeriodicWaveOptions(imag: [0, 1]))
        let fromOptions = try OscillatorNode(
            context: context,
            options: OscillatorOptions(type: .square, frequency: 375, periodicWave: wave)
        )
        #expect(fromOptions.type == .custom && fromOptions.frequency.value == 375)
        try fromOptions.connect(context.destination)
        try fromOptions.start()
        oscillator.frequency.value = 0
    }
    #expect(largestDifference(samples, { sine(375, frame: Double($0)) }, in: 0 ..< 512) < 1e-4)
}

@MainActor
@Test func oscillatorErrors() throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: sampleRate)
    let oscillator = context.createOscillator()
    #expect(throws: WebAudioError.invalidState) { try oscillator.setType(.custom) }
    #expect(throws: WebAudioError.invalidState) { try oscillator.stop() }
    #expect(throws: WebAudioError.rangeError) { try oscillator.start(-1) }
    try oscillator.start()
    #expect(throws: WebAudioError.invalidState) { try oscillator.start() }
    #expect(throws: WebAudioError.rangeError) { try oscillator.stop(-1) }

    #expect(throws: WebAudioError.invalidState) {
        try OscillatorNode(context: context, options: OscillatorOptions(type: .custom))
    }
    #expect(throws: WebAudioError.rangeError) {
        try OscillatorNode(context: context, options: OscillatorOptions(frequency: .nan))
    }
}

@MainActor
@Test func periodicWaveErrors() throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: sampleRate)
    #expect(throws: WebAudioError.indexSize) {
        try context.createPeriodicWave(real: [0, 1], imag: [0, 1, 0])
    }
    #expect(throws: WebAudioError.indexSize) {
        try PeriodicWave(context: context, options: PeriodicWaveOptions(real: [0, 1], imag: [0, 1, 0]))
    }
    #expect(throws: WebAudioError.indexSize) {
        try PeriodicWave(context: context, options: PeriodicWaveOptions(real: [1]))
    }
    #expect(throws: WebAudioError.indexSize) {
        try PeriodicWave(context: context, options: PeriodicWaveOptions(imag: [1]))
    }
    #expect(throws: WebAudioError.rangeError) {
        try PeriodicWave(context: context, options: PeriodicWaveOptions(imag: [0, .infinity]))
    }
}
