import Echo
import Foundation
import Testing

private let sampleRate: Float = 48_000

// The channels of what `context` renders. getChannelData's pointer is valid
// only while the buffer is, so the samples are copied out.
@MainActor
private func rendered(_ context: OfflineAudioContext) async throws -> [[Float]] {
    let buffer = try await context.startRendering()
    return try (0 ..< buffer.numberOfChannels).map { channel in
        var samples = [Float](repeating: 0, count: Int(buffer.length))
        try buffer.copyFromChannel(&samples, channelNumber: channel)
        return samples
    }
}

// A constant 1 from frame 0 through a filter set up by `configure`.
@MainActor
private func stepResponse(
    length: UInt32 = 512,
    configure: (BiquadFilterNode) throws -> Void
) async throws -> [Float] {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: length, sampleRate: sampleRate)
    let source = context.createConstantSource()
    let filter = context.createBiquadFilter()
    try configure(filter)
    try source.connect(filter).connect(context.destination)
    try source.start()
    return try await rendered(context)[0]
}

// The specification's coefficients, written out again here, as (b0, b1, b2,
// a0, a1, a2).
private func specificationCoefficients(
    _ type: BiquadFilterType, f0: Double, q: Double, g: Double
) -> [Double] {
    let a = pow(10, g / 40)
    let w0 = 2 * Double.pi * f0 / Double(sampleRate)
    let alphaQ = sin(w0) / (2 * q)
    let alphaQDB = sin(w0) / (2 * pow(10, q / 20))
    let alphaS = sin(w0) / 2 * sqrt((a + 1 / a) * (1 / 1 - 1) + 2)
    let c = cos(w0)
    switch type {
    case .lowpass: return [(1 - c) / 2, 1 - c, (1 - c) / 2, 1 + alphaQDB, -2 * c, 1 - alphaQDB]
    case .highpass: return [(1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + alphaQDB, -2 * c, 1 - alphaQDB]
    case .bandpass: return [alphaQ, 0, -alphaQ, 1 + alphaQ, -2 * c, 1 - alphaQ]
    case .notch: return [1, -2 * c, 1, 1 + alphaQ, -2 * c, 1 - alphaQ]
    case .allpass: return [1 - alphaQ, -2 * c, 1 + alphaQ, 1 + alphaQ, -2 * c, 1 - alphaQ]
    case .peaking: return [1 + alphaQ * a, -2 * c, 1 - alphaQ * a, 1 + alphaQ / a, -2 * c, 1 - alphaQ / a]
    case .lowshelf:
        return [
            a * ((a + 1) - (a - 1) * c + 2 * alphaS * sqrt(a)), 2 * a * ((a - 1) - (a + 1) * c),
            a * ((a + 1) - (a - 1) * c - 2 * alphaS * sqrt(a)), (a + 1) + (a - 1) * c + 2 * alphaS * sqrt(a),
            -2 * ((a - 1) + (a + 1) * c), (a + 1) + (a - 1) * c - 2 * alphaS * sqrt(a),
        ]
    case .highshelf:
        return [
            a * ((a + 1) + (a - 1) * c + 2 * alphaS * sqrt(a)), -2 * a * ((a - 1) + (a + 1) * c),
            a * ((a + 1) + (a - 1) * c - 2 * alphaS * sqrt(a)), (a + 1) - (a - 1) * c + 2 * alphaS * sqrt(a),
            2 * ((a - 1) - (a + 1) * c), (a + 1) - (a - 1) * c - 2 * alphaS * sqrt(a),
        ]
    }
}

// a0 y(n) + a1 y(n-1) + a2 y(n-2) = b0 x(n) + b1 x(n-1) + b2 x(n-2), from a
// state of 0, for a constant 1.
private func referenceStepResponse(_ coefficients: [Double], length: Int) -> [Double] {
    let (b0, b1, b2, a0, a1, a2) = (
        coefficients[0], coefficients[1], coefficients[2], coefficients[3], coefficients[4], coefficients[5]
    )
    var (x1, x2, y1, y2) = (0.0, 0.0, 0.0, 0.0)
    return (0 ..< length).map { _ in
        let y = (b0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
        (x2, x1, y2, y1) = (x1, 1, y1, y)
        return y
    }
}

@MainActor
@Test func biquadFilterHasTheSpecifiedDefaults() throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: sampleRate)
    let filter = context.createBiquadFilter()
    #expect(filter.type == .lowpass)
    #expect(filter.numberOfInputs == 1 && filter.numberOfOutputs == 1)
    #expect(filter.channelCount == 2 && filter.channelCountMode == .max && filter.channelInterpretation == .speakers)
    #expect(filter.frequency.defaultValue == 350 && filter.frequency.minValue == 0)
    #expect(filter.frequency.maxValue == sampleRate / 2)
    #expect(filter.detune.defaultValue == 0 && abs(filter.detune.maxValue - 153_600) < 1)
    #expect(filter.Q.defaultValue == 1 && filter.Q.maxValue == .greatestFiniteMagnitude)
    #expect(filter.gain.defaultValue == 0 && abs(filter.gain.maxValue - 1541.27) < 0.01)
    for param in [filter.frequency, filter.detune, filter.Q, filter.gain] {
        #expect(param.automationRate == .aRate)
    }
}

@MainActor
@Test(arguments: BiquadFilterType.allCases)
func biquadFilterFollowsTheSpecifiedCoefficients(type: BiquadFilterType) async throws {
    let samples = try await stepResponse { filter in
        filter.type = type
        filter.frequency.value = 1000
        filter.Q.value = 2
        filter.gain.value = 6
    }
    let reference = referenceStepResponse(specificationCoefficients(type, f0: 1000, q: 2, g: 6), length: 512)
    let difference = zip(samples, reference).map { abs(Double($0) - $1) }.max()!
    #expect(difference < 1e-5, "\(type): \(difference)")
}

@MainActor
@Test func filterFrequencyAndDetuneAreClampedOnlyTogether() async throws {
    // 30 kHz is beyond the Nyquist frequency alone, but an octave down it is
    // 15 kHz, which the filter uses.
    let samples = try await stepResponse { filter in
        filter.frequency.value = 30_000
        filter.detune.value = -1200
    }
    let reference = referenceStepResponse(specificationCoefficients(.lowpass, f0: 15_000, q: 1, g: 0), length: 512)
    #expect(zip(samples, reference).allSatisfy { abs(Double($0) - $1) < 1e-5 })
}

@MainActor
@Test(arguments: [
    (BiquadFilterType.bandpass, Float(1)),
    (.notch, 0),
    (.allpass, -1),
    // A² = 10^(6/20).
    (.peaking, 1.9952623),
])
func zeroQGivesTheLimitOfTheTransferFunction(type: BiquadFilterType, expected: Float) async throws {
    let samples = try await stepResponse { filter in
        filter.type = type
        filter.Q.value = 0
        filter.gain.value = 6
    }
    #expect(samples.allSatisfy { abs($0 - expected) < 1e-5 }, "\(type): \(samples[0])")
}

@MainActor
@Test func biquadFilterKeepsTheInputChannels() async throws {
    // Stereo with only the left channel, from a panner hard left.
    let context = try OfflineAudioContext(numberOfChannels: 2, length: 256, sampleRate: sampleRate)
    let source = context.createConstantSource()
    let panner = try StereoPannerNode(context: context, options: StereoPannerOptions(pan: -1))
    let filter = try BiquadFilterNode(context: context, options: BiquadFilterOptions(frequency: 1000))
    try source.connect(panner).connect(filter).connect(context.destination)
    try source.start()
    let channels = try await rendered(context)
    let reference = referenceStepResponse(specificationCoefficients(.lowpass, f0: 1000, q: 1, g: 0), length: 256)
    #expect(zip(channels[0], reference).allSatisfy { abs(Double($0) - $1) < 1e-5 })
    #expect(channels[1].allSatisfy { $0 == 0 })
}

@MainActor
@Test func frequencyResponse() throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: sampleRate)
    let filter = try BiquadFilterNode(
        context: context,
        options: BiquadFilterOptions(type: .peaking, Q: 2, frequency: 1000, gain: 6)
    )
    let frequencies: [Float] = [0, 1000, 24_000, -1, 24_001]
    var magnitudes = [Float](repeating: 0, count: 5)
    var phases = [Float](repeating: 0, count: 5)
    try filter.getFrequencyResponse(frequencies, &magnitudes, &phases)
    // A peak of A² = 10^(6/20) at the center, and none at 0 or Nyquist.
    #expect(abs(magnitudes[0] - 1) < 1e-5 && abs(phases[0]) < 1e-5)
    #expect(abs(magnitudes[1] - 1.9952623) < 1e-4 && abs(phases[1]) < 1e-4)
    #expect(abs(magnitudes[2] - 1) < 1e-4)
    #expect(magnitudes[3].isNaN && phases[3].isNaN && magnitudes[4].isNaN && phases[4].isNaN)

    var short = [Float](repeating: 0, count: 4)
    #expect(throws: WebAudioError.invalidAccess) {
        try filter.getFrequencyResponse(frequencies, &short, &phases)
    }
}

@MainActor
@Test func biquadFilterOptionsAreChecked() throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: sampleRate)
    for options in [
        BiquadFilterOptions(Q: .nan), BiquadFilterOptions(detune: .infinity),
        BiquadFilterOptions(frequency: .nan), BiquadFilterOptions(gain: -.infinity),
    ] {
        #expect(throws: WebAudioError.rangeError) { try BiquadFilterNode(context: context, options: options) }
    }
    let filter = try BiquadFilterNode(
        context: context,
        options: BiquadFilterOptions(type: .highshelf, Q: 3, detune: 100, frequency: 2000, gain: -3)
    )
    #expect(filter.type == .highshelf && filter.Q.value == 3 && filter.detune.value == 100)
    #expect(filter.frequency.value == 2000 && filter.gain.value == -3)
}
