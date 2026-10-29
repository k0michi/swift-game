import Echo
import Foundation
import Testing

// Renders a constant `input` through a WaveShaperNode set up by `configure`.
@MainActor
private func shaped(
    _ input: Float,
    length: UInt32 = 128,
    configure: (WaveShaperNode) throws -> Void
) async throws -> [Float] {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: length, sampleRate: 48_000)
    let source = context.createConstantSource()
    source.offset.value = input
    let shaper = context.createWaveShaper()
    try configure(shaper)
    try source.connect(shaper).connect(context.destination)
    try source.start()
    return try await rendered(context)
}

// The first channel of what `context` renders. getChannelData's pointer is
// valid only while the buffer is, so the samples are copied out.
@MainActor
private func rendered(_ context: OfflineAudioContext) async throws -> [Float] {
    let buffer = try await context.startRendering()
    var samples = [Float](repeating: 0, count: Int(buffer.length))
    try buffer.copyFromChannel(&samples, channelNumber: 0)
    return samples
}

@MainActor
@Test func waveShaperHasTheSpecifiedDefaults() throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    let shaper = context.createWaveShaper()
    #expect(shaper.curve == nil)
    #expect(shaper.oversample == .none)
    #expect(shaper.numberOfInputs == 1 && shaper.numberOfOutputs == 1)
    #expect(shaper.channelCount == 2)
    #expect(shaper.channelCountMode == .max)
    #expect(shaper.channelInterpretation == .speakers)
}

@MainActor
@Test func waveShaperWithoutCurvePassesInputThrough() async throws {
    let samples = try await shaped(0.3) { _ in }
    #expect(samples.allSatisfy { abs($0 - 0.3) < 1e-6 })
}

@MainActor
@Test(arguments: [
    // v = (N - 1) / 2 * (x + 1) over the curve [0, 1, 4].
    (Float(-0.5), Float(0.5)),
    (0, 1),
    (0.5, 2.5),
    (-1, 0),
    (1, 4),
    // Beyond [-1, 1], the first or last value.
    (-2, 0),
    (3, 4),
])
func waveShaperInterpolatesTheCurveLinearly(input: Float, expected: Float) async throws {
    let samples = try await shaped(input) { try $0.setCurve([0, 1, 4]) }
    #expect(samples.allSatisfy { abs($0 - expected) < 1e-6 }, "\(input) -> \(samples[0])")
}

@MainActor
@Test func waveShaperWithEvenCurveInterpolatesAtZero() async throws {
    // 0 falls between the two middle values of an even curve.
    let samples = try await shaped(0) { try $0.setCurve([0, 1, 3, 7]) }
    #expect(samples.allSatisfy { abs($0 - 2) < 1e-6 })
}

@MainActor
@Test func waveShaperCurveFromOptions() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    let source = context.createConstantSource()
    source.offset.value = 0.5
    let shaper = try WaveShaperNode(context: context, options: WaveShaperOptions(curve: [-1, 3]))
    #expect(shaper.curve == [-1, 3])
    try source.connect(shaper).connect(context.destination)
    try source.start()
    let samples = try await rendered(context)
    #expect(samples.allSatisfy { abs($0 - 2) < 1e-6 })
}

@MainActor
@Test func waveShaperMakesDCWithoutInput() async throws {
    // A curve whose value at 0 is not 0 shapes the silence of no input.
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    let shaper = context.createWaveShaper()
    try shaper.setCurve([0.25, 0.25])
    try shaper.connect(context.destination)
    let samples = try await rendered(context)
    #expect(samples.allSatisfy { abs($0 - 0.25) < 1e-6 })
}

@MainActor
@Test func waveShaperCurveIsSetOnlyOnce() throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    let shaper = context.createWaveShaper()
    #expect(throws: WebAudioError.invalidState) { try shaper.setCurve([1]) }
    #expect(throws: WebAudioError.invalidState) { try shaper.setCurve([]) }
    // A curve too short does not count as set.
    try shaper.setCurve([0, 1])
    #expect(throws: WebAudioError.invalidState) { try shaper.setCurve([1, 0]) }
    // null may be set, but the curve has still been set.
    try shaper.setCurve(nil)
    #expect(shaper.curve == nil)
    #expect(throws: WebAudioError.invalidState) { try shaper.setCurve([1, 0]) }

    let fromOptions = try WaveShaperNode(context: context, options: WaveShaperOptions(curve: [0, 1]))
    #expect(throws: WebAudioError.invalidState) { try fromOptions.setCurve([1, 0]) }
}

@MainActor
@Test func waveShaperOptionsAreChecked() throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    #expect(throws: WebAudioError.invalidState) {
        try WaveShaperNode(context: context, options: WaveShaperOptions(curve: [1]))
    }
    // The option is a sequence<float>, unlike the attribute's Float32Array.
    #expect(throws: WebAudioError.rangeError) {
        try WaveShaperNode(context: context, options: WaveShaperOptions(curve: [0, .nan]))
    }
    try context.createWaveShaper().setCurve([0, .infinity])
    #expect(throws: WebAudioError.notSupported) {
        try WaveShaperNode(context: context, options: WaveShaperOptions(channelCount: 0))
    }
    let shaper = try WaveShaperNode(
        context: context,
        options: WaveShaperOptions(channelCount: 1, channelCountMode: .explicit, oversample: .`4x`)
    )
    #expect(shaper.channelCount == 1 && shaper.channelCountMode == .explicit && shaper.oversample == .`4x`)
}

@MainActor
@Test(arguments: [OverSampleType.`2x`, .`4x`])
func waveShaperOversamplesWithLatency(oversample: OverSampleType) async throws {
    // |x| over [-1, 1], whose value at 0.5 is 0.5 once the filters settle.
    let samples = try await shaped(0.5, length: 512) { shaper in
        try shaper.setCurve([1, 0, 1])
        shaper.oversample = oversample
    }
    #expect(abs(samples[0]) < 0.1, "the filters delay the start: \(samples[0])")
    #expect(samples[256...].allSatisfy { abs($0 - 0.5) < 1e-3 }, "\(samples[256])")
}

@MainActor
@Test(arguments: [(OverSampleType.`2x`, 15.0), (.`4x`, 22.5)])
func waveShaperOversamplingKeepsALowTone(oversample: OverSampleType, latency: Double) async throws {
    // A 375 Hz sine, far below the Nyquist frequency, through the identity
    // curve comes out as itself, later by the filters' latency: 15 taps of
    // each of the 2x filters, a 4x filter's being half as long.
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 1024, sampleRate: 48_000)
    let shaper = context.createWaveShaper()
    try shaper.setCurve([-1, 1])
    shaper.oversample = oversample
    func sine(_ frame: Double) -> Double { sin(2 * .pi * 375 * frame / 48_000) }
    // Echo has no oscillator or buffer source yet, so a constant source
    // follows the sine as a value curve, a point on each frame.
    let source = context.createConstantSource()
    try source.offset.setValueCurveAtTime(
        (0 ..< 1024).map { Float(sine(Double($0))) }, startTime: 0, duration: 1023 / 48_000
    )
    try source.connect(shaper).connect(context.destination)
    try source.start()
    let samples = try await rendered(context)
    // The best match of the input, delayed by a quarter frame at a time.
    let (delay, error) = stride(from: 0.0, through: 40, by: 0.25).map { delay in
        (delay, (512 ..< 1000).map { abs(Double(samples[$0]) - sine(Double($0) - delay)) }.max()!)
    }.min { $0.1 < $1.1 }!
    #expect(delay == latency)
    #expect(error < 0.005, "delayed by \(delay), off by \(error)")
}
