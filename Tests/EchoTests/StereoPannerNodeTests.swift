import Echo
import Foundation
import Testing

// The left and right channels of what `context` renders. getChannelData's
// pointer is valid only while the buffer is, so the samples are copied out.
@MainActor
private func renderedStereo(_ context: OfflineAudioContext) async throws -> (left: [Float], right: [Float]) {
    let buffer = try await context.startRendering()
    var left = [Float](repeating: 0, count: Int(buffer.length))
    var right = left
    try buffer.copyFromChannel(&left, channelNumber: 0)
    try buffer.copyFromChannel(&right, channelNumber: 1)
    return (left, right)
}

// Pans a constant 1, mono, or stereo with only the left channel when
// `stereo` is set: a first panner hard left makes that.
@MainActor
private func panned(_ pan: Float, stereo: Bool = false, configure: (OfflineAudioContext, StereoPannerNode) throws -> Void = { _, _ in })
    async throws -> (left: [Float], right: [Float])
{
    let context = try OfflineAudioContext(numberOfChannels: 2, length: 128, sampleRate: 48_000)
    let source = context.createConstantSource()
    let panner = context.createStereoPanner()
    panner.pan.value = pan
    try configure(context, panner)
    if stereo {
        let hardLeft = try StereoPannerNode(context: context, options: StereoPannerOptions(pan: -1))
        try source.connect(hardLeft).connect(panner)
    } else {
        try source.connect(panner)
    }
    try panner.connect(context.destination)
    try source.start()
    return try await renderedStereo(context)
}

private func isConstant(_ samples: [Float], _ expected: Float) -> Bool {
    samples.allSatisfy { abs($0 - expected) < 1e-6 }
}

@MainActor
@Test func stereoPannerHasTheSpecifiedDefaults() throws {
    let context = try OfflineAudioContext(numberOfChannels: 2, length: 128, sampleRate: 48_000)
    let panner = context.createStereoPanner()
    #expect(panner.numberOfInputs == 1 && panner.numberOfOutputs == 1)
    #expect(panner.channelCount == 2 && panner.channelCountMode == .clampedMax)
    #expect(panner.channelInterpretation == .speakers)
    #expect(panner.pan.defaultValue == 0 && panner.pan.minValue == -1 && panner.pan.maxValue == 1)
    #expect(panner.pan.automationRate == .aRate)
}

@MainActor
@Test(arguments: [Float(-1), -0.5, 0, 0.5, 1])
func stereoPannerPansMonoWithEqualPower(pan: Float) async throws {
    let (left, right) = try await panned(pan)
    let x = (Double(pan) + 1) / 2
    #expect(isConstant(left, Float(cos(x * .pi / 2))), "\(pan): \(left[0])")
    #expect(isConstant(right, Float(sin(x * .pi / 2))), "\(pan): \(right[0])")
}

@MainActor
@Test func stereoPannerMovesStereoTowardOneSide() async throws {
    // The input is 1 on the left and 0 on the right. Panning right moves part
    // of the left into the right; panning left keeps the left whole.
    let half = Float(cos(Double.pi / 4))
    let right = try await panned(0.5, stereo: true)
    #expect(isConstant(right.left, half) && isConstant(right.right, half), "\(right.left[0]) \(right.right[0])")
    let left = try await panned(-0.5, stereo: true)
    #expect(isConstant(left.left, 1) && isConstant(left.right, 0), "\(left.left[0]) \(left.right[0])")
    let center = try await panned(0, stereo: true)
    #expect(isConstant(center.left, 1) && isConstant(center.right, 0))
}

@MainActor
@Test func stereoPannerClampsTheComputedPan() async throws {
    // 0.5 connected to a pan of 0.75 makes 1.25, clamped to hard right.
    let (left, right) = try await panned(0.75) { context, panner in
        let modulation = context.createConstantSource()
        modulation.offset.value = 0.5
        try modulation.connect(panner.pan)
        try modulation.start()
    }
    #expect(left.allSatisfy { abs($0) < 1e-6 } && isConstant(right, 1), "\(left[0]) \(right[0])")
}

@MainActor
@Test func stereoPannerDownMixesMoreThanTwoChannels() async throws {
    // With "explicit" and one channel, a stereo input is mixed down to mono
    // first: (1 + 0) / 2 at the center.
    let (left, right) = try await panned(0, stereo: true) { _, panner in
        try panner.setChannelCount(1)
        try panner.setChannelCountMode(.explicit)
    }
    let expected = Float(0.5 * cos(Double.pi / 4))
    #expect(isConstant(left, expected) && isConstant(right, expected), "\(left[0]) \(right[0])")
}

@MainActor
@Test func stereoPannerChannelsAreConstrained() throws {
    let context = try OfflineAudioContext(numberOfChannels: 2, length: 128, sampleRate: 48_000)
    let panner = context.createStereoPanner()
    #expect(throws: WebAudioError.notSupported) { try panner.setChannelCount(3) }
    #expect(throws: WebAudioError.notSupported) { try panner.setChannelCountMode(.max) }
    try panner.setChannelCount(1)
    try panner.setChannelCountMode(.explicit)
    #expect(panner.channelCount == 1 && panner.channelCountMode == .explicit)

    #expect(throws: WebAudioError.notSupported) {
        try StereoPannerNode(context: context, options: StereoPannerOptions(channelCount: 3))
    }
    #expect(throws: WebAudioError.notSupported) {
        try StereoPannerNode(context: context, options: StereoPannerOptions(channelCountMode: .max))
    }
    #expect(throws: WebAudioError.rangeError) {
        try StereoPannerNode(context: context, options: StereoPannerOptions(pan: .nan))
    }
    let fromOptions = try StereoPannerNode(context: context, options: StereoPannerOptions(pan: -0.25))
    #expect(fromOptions.pan.value == -0.25)
}
