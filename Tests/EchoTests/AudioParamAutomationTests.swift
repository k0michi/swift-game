import Echo
import Testing

@MainActor
@Test func audioParamLinearRampUsesExactSampleTimes() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 256, sampleRate: 48_000)
    let source = context.createConstantSource()
    try source.offset.setValueAtTime(0, startTime: 0)
        .linearRampToValueAtTime(1, endTime: 128.0 / 48_000)
    try source.start()
    try source.connect(context.destination)

    let buffer = try await context.startRendering()
    let samples = try buffer.getChannelData(0)
    #expect(samples[0] == 0)
    #expect(abs(samples[64] - 0.5) < 0.0001)
    #expect(abs(samples[127] - 127.0 / 128) < 0.0001)
    #expect(samples[128] == 1)
}

@MainActor
@Test func audioParamExponentialTargetAndCurveAreSampleAccurate() async throws {
    let exponential = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    let expSource = exponential.createConstantSource()
    try expSource.offset.setValueAtTime(1, startTime: 0)
        .exponentialRampToValueAtTime(4, endTime: 128.0 / 48_000)
    try expSource.start()
    try expSource.connect(exponential.destination)
    let expBuffer = try await exponential.startRendering()
    let expSamples = try expBuffer.getChannelData(0)
    #expect(abs(expSamples[64] - 2) < 0.0001)

    let target = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    let targetSource = target.createConstantSource()
    try targetSource.offset.setValueAtTime(0, startTime: 0)
        .setTargetAtTime(1, startTime: 0, timeConstant: 64.0 / 48_000)
    try targetSource.start()
    try targetSource.connect(target.destination)
    let targetBuffer = try await target.startRendering()
    let targetSamples = try targetBuffer.getChannelData(0)
    #expect(abs(targetSamples[64] - 0.63212055) < 0.0001)

    let curve = try OfflineAudioContext(numberOfChannels: 1, length: 256, sampleRate: 48_000)
    let curveSource = curve.createConstantSource()
    try curveSource.offset.setValueCurveAtTime([0, 1, 0], startTime: 0, duration: 128.0 / 48_000)
    try curveSource.start()
    try curveSource.connect(curve.destination)
    let curveBuffer = try await curve.startRendering()
    let curveSamples = try curveBuffer.getChannelData(0)
    #expect(abs(curveSamples[32] - 0.5) < 0.0001)
    #expect(abs(curveSamples[64] - 1) < 0.0001)
    #expect(abs(curveSamples[96] - 0.5) < 0.0001)
    #expect(curveSamples[128] == 0)
}

@MainActor
@Test func audioParamCancelAndHoldPreservesPartialRamp() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    let source = context.createConstantSource()
    try source.offset.setValueAtTime(0, startTime: 0)
        .linearRampToValueAtTime(1, endTime: 128.0 / 48_000)
        .cancelAndHoldAtTime(64.0 / 48_000)
    try source.start()
    try source.connect(context.destination)

    let buffer = try await context.startRendering()
    let samples = try buffer.getChannelData(0)
    #expect(abs(samples[32] - 0.25) < 0.0001)
    #expect(abs(samples[64] - 0.5) < 0.0001)
    #expect(abs(samples[127] - 0.5) < 0.0001)
}

@MainActor
@Test func kRateSamplesAutomationAndModulationOncePerQuantum() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 256, sampleRate: 48_000)
    let modulator = context.createConstantSource()
    let source = context.createConstantSource()
    try modulator.offset.setValueAtTime(0, startTime: 0)
        .linearRampToValueAtTime(1, endTime: 128.0 / 48_000)
    source.offset.value = 0
    source.offset.automationRate = .kRate
    try modulator.start()
    try source.start()
    try modulator.connect(source.offset)
    try source.connect(context.destination)

    let buffer = try await context.startRendering()
    let samples = try buffer.getChannelData(0)
    #expect(samples[0] == 0)
    #expect(samples[127] == 0)
    #expect(samples[128] == 1)
    #expect(samples[255] == 1)
}

@MainActor
@Test func audioParamRejectsInvalidEventsAndCurveOverlap() throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    let parameter = context.createConstantSource().offset
    #expect(throws: WebAudioError.rangeError) {
        try parameter.setValueAtTime(1, startTime: -.infinity)
    }
    #expect(throws: WebAudioError.rangeError) {
        try parameter.exponentialRampToValueAtTime(0, endTime: 1)
    }
    #expect(throws: WebAudioError.invalidState) {
        try parameter.setValueCurveAtTime([1], startTime: 0, duration: 1)
    }
    try parameter.setValueCurveAtTime([0, 1], startTime: 0, duration: 1)
    #expect(throws: WebAudioError.notSupported) {
        try parameter.setValueAtTime(0.5, startTime: 0.5)
    }
    try parameter.cancelAndHoldAtTime(0.5)
    try parameter.setValueAtTime(0.25, startTime: 0.75)
}

@MainActor
@Test func targetToRampTransitionKeepsItsCurrentValue() async throws {
    let context = try OfflineAudioContext(options: OfflineAudioContextOptions(
        numberOfChannels: 1,
        length: 128,
        sampleRate: 48_000,
        renderSizeHint: .frameCount(64)
    ))
    let source = context.createConstantSource()
    try source.offset.setValueAtTime(0, startTime: 0)
        .setTargetAtTime(1, startTime: 0, timeConstant: 64.0 / 48_000)
    try source.start()
    try source.connect(context.destination)

    let suspension = Task { try await context.suspend(at: 64.0 / 48_000) }
    await Task.yield()
    let rendering = Task { () throws -> [Float] in
        let buffer = try await context.startRendering()
        return Array(try buffer.getChannelData(0))
    }
    try await suspension.value
    try source.offset.linearRampToValueAtTime(0, endTime: 128.0 / 48_000)
    try await context.resume()

    let samples = try await rendering.value
    #expect(abs(samples[32] - 0.39346933) < 0.0001)
    #expect(abs(samples[64] - 0.63212055) < 0.0001)
    #expect(abs(samples[96] - 0.31606027) < 0.0001)
}

@MainActor
@Test func cancellingAndHoldingCurvePreservesItsEarlierShape() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    let source = context.createConstantSource()
    try source.offset.setValueCurveAtTime([0, 1, 0], startTime: 0, duration: 128.0 / 48_000)
        .cancelAndHoldAtTime(64.0 / 48_000)
    try source.start()
    try source.connect(context.destination)

    let buffer = try await context.startRendering()
    let samples = try buffer.getChannelData(0)
    #expect(abs(samples[32] - 0.5) < 0.0001)
    #expect(abs(samples[64] - 1) < 0.0001)
    #expect(abs(samples[127] - 1) < 0.0001)
}

@MainActor
@Test func cancellingFutureRampRestoresPreviousValue() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    let source = context.createConstantSource()
    try source.offset.setValueAtTime(0, startTime: 0)
        .linearRampToValueAtTime(1, endTime: 128.0 / 48_000)
        .cancelScheduledValues(64.0 / 48_000)
    try source.start()
    try source.connect(context.destination)

    let buffer = try await context.startRendering()
    #expect(try buffer.getChannelData(0).allSatisfy { $0 == 0 })
}

@MainActor
@Test func cancellingActiveTargetRestoresPreviousValue() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    let source = context.createConstantSource()
    try source.offset.setValueAtTime(0, startTime: 0)
        .setTargetAtTime(1, startTime: 0, timeConstant: 64.0 / 48_000)
        .cancelScheduledValues(64.0 / 48_000)
    try source.start()
    try source.connect(context.destination)

    let buffer = try await context.startRendering()
    let samples = try buffer.getChannelData(0)
    #expect(abs(samples[32] - 0.39346933) < 0.0001)
    #expect(samples[64] == 0)
    #expect(samples[127] == 0)
}

@MainActor
@Test func sameTimeEventsKeepInsertionOrder() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    let source = context.createConstantSource()
    try source.offset.setValueAtTime(0.25, startTime: 0)
        .setValueAtTime(0.75, startTime: 0)
    try source.start()
    try source.connect(context.destination)

    let buffer = try await context.startRendering()
    #expect(try buffer.getChannelData(0)[0] == 0.75)
}

@MainActor
@Test func automationScheduledWhileSuspendedReplacesRenderSnapshot() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 256, sampleRate: 48_000)
    let source = context.createConstantSource()
    source.offset.value = 0
    try source.start()
    try source.connect(context.destination)

    let suspension = Task { try await context.suspend(at: 128.0 / 48_000) }
    await Task.yield()
    let rendering = Task { () throws -> [Float] in
        let buffer = try await context.startRendering()
        return Array(try buffer.getChannelData(0))
    }
    try await suspension.value
    try source.offset.setValueAtTime(1, startTime: 128.0 / 48_000)
    try await context.resume()

    let samples = try await rendering.value
    #expect(samples[127] == 0)
    #expect(samples[128] == 1)
}
