import Echo
import Testing

@MainActor
@Test func delayBreaksFeedbackCycleAtOneQuantum() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 384, sampleRate: 48_000)
    let source = context.createConstantSource()
    let delay = try context.createDelay(0.001)
    try source.start()
    try source.connect(delay)
    try delay.connect(delay)
    try delay.connect(context.destination)

    let buffer = try await context.startRendering()
    let samples = Array(try buffer.getChannelData(0))
    #expect(abs(samples[0]) < 0.001)
    #expect(abs(samples[128] - 1) < 0.001)
    #expect(abs(samples[256] - 2) < 0.001)
}

@MainActor
@Test func twoDelaysBreakTheSameFeedbackCycle() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 512, sampleRate: 48_000)
    let source = context.createConstantSource()
    let first = try context.createDelay()
    let second = try context.createDelay()
    try source.start()
    try source.connect(first)
    try first.connect(second)
    try second.connect(first)
    try first.connect(context.destination)

    let buffer = try await context.startRendering()
    let samples = try buffer.getChannelData(0)
    #expect(abs(samples[0]) < 0.001)
    #expect(abs(samples[128] - 1) < 0.001)
    #expect(abs(samples[256] - 1) < 0.001)
    #expect(abs(samples[384] - 2) < 0.001)
}

@MainActor
@Test func delayBreaksCycleThroughAudioParam() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 384, sampleRate: 48_000)
    let source = context.createConstantSource()
    let delay = try context.createDelay()
    try source.start()
    try source.connect(delay)
    try delay.connect(source.offset)
    try delay.connect(context.destination)

    let buffer = try await context.startRendering()
    let samples = try buffer.getChannelData(0)
    #expect(abs(samples[0]) < 0.001)
    #expect(abs(samples[128] - 1) < 0.001)
    #expect(abs(samples[256] - 2) < 0.001)
}

@MainActor
@Test func cycleThroughDelayTimeRemainsMuted() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    let source = context.createConstantSource()
    let delay = try context.createDelay()
    try source.start()
    try source.connect(delay)
    try delay.connect(delay.delayTime)
    try delay.connect(context.destination)

    let buffer = try await context.startRendering()
    #expect(try buffer.getChannelData(0).allSatisfy { $0 == 0 })
}

@MainActor
@Test func delayRetainsSamplesAcrossRenderPlanReplacement() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 384, sampleRate: 48_000)
    let source = context.createConstantSource()
    let delay = try context.createDelay()
    source.offset.value = 1
    try source.start()
    try source.stop(1.0 / 48_000)
    delay.delayTime.value = 128.0 / 48_000
    try source.connect(delay)
    try delay.connect(context.destination)

    let suspension = Task { try await context.suspend(at: 128.0 / 48_000) }
    await Task.yield()
    let rendering = Task { () throws -> [Float] in
        let buffer = try await context.startRendering()
        return Array(try buffer.getChannelData(0))
    }
    try await suspension.value
    delay.delayTime.value = 256.0 / 48_000
    try await context.resume()

    let samples = try await rendering.value
    #expect(samples[0] == 0)
    #expect(abs(samples[127]) < 0.001)
    #expect(abs(samples[128]) < 0.001)
    #expect(abs(samples[256] - 1) < 0.001)
    #expect(samples[257] < 0.001)
}

@MainActor
@Test func delayRetainsSamplesAcrossOfflineChunks() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 256, sampleRate: 48_000)
    let source = context.createConstantSource()
    let delay = try context.createDelay()
    try source.start()
    try source.stop(1.0 / 48_000)
    delay.delayTime.value = 128.0 / 48_000
    try source.connect(delay)
    try delay.connect(context.destination)

    let first = try await context.startRendering(chunkSize: 128)
    source.offset.value = 0.5
    let second = try await context.startRendering()

    #expect(try first.getChannelData(0).allSatisfy { abs($0) < 0.001 })
    #expect(abs(try second.getChannelData(0)[0] - 1) < 0.001)
}

@MainActor
@Test func delayTailSurvivesInputDisconnection() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 384, sampleRate: 48_000)
    let source = context.createConstantSource()
    let delay = try context.createDelay()
    try source.start()
    try source.stop(1.0 / 48_000)
    delay.delayTime.value = 256.0 / 48_000
    try source.connect(delay)
    try delay.connect(context.destination)

    _ = try await context.startRendering(chunkSize: 128)
    try source.disconnect(delay)
    _ = try await context.startRendering(chunkSize: 128)
    let tail = try await context.startRendering()

    #expect(abs(try tail.getChannelData(0)[0] - 1) < 0.001)
}

@MainActor
@Test func delayChannelCountModeControlsInputAndOutputLayout() async throws {
    let maximum = try OfflineAudioContext(numberOfChannels: 2, length: 128, sampleRate: 48_000)
    let monoSource = maximum.createConstantSource()
    let maxDelay = try maximum.createDelay()
    try monoSource.start()
    try monoSource.connect(maxDelay)
    try maxDelay.connect(maximum.destination)
    maximum.destination.setChannelInterpretation(.discrete)
    let maxBuffer = try await maximum.startRendering()
    #expect(try maxBuffer.getChannelData(0)[0] == 1)
    #expect(try maxBuffer.getChannelData(1)[0] == 0)

    let explicit = try OfflineAudioContext(numberOfChannels: 2, length: 128, sampleRate: 48_000)
    let explicitSource = explicit.createConstantSource()
    let stereoDelay = try DelayNode(context: explicit, options: DelayOptions(
        channelCount: 2,
        channelCountMode: .explicit
    ))
    try explicitSource.start()
    try explicitSource.connect(stereoDelay)
    try stereoDelay.connect(explicit.destination)
    explicit.destination.setChannelInterpretation(.discrete)
    let explicitBuffer = try await explicit.startRendering()
    #expect(try explicitBuffer.getChannelData(0)[0] == 1)
    #expect(try explicitBuffer.getChannelData(1)[0] == 1)

    let clamped = try OfflineAudioContext(numberOfChannels: 2, length: 128, sampleRate: 48_000)
    let clampedSource = clamped.createConstantSource()
    let upstream = try DelayNode(context: clamped, options: DelayOptions(channelCountMode: .explicit))
    let downstream = try DelayNode(context: clamped, options: DelayOptions(
        channelCount: 1,
        channelCountMode: .clampedMax
    ))
    try clampedSource.start()
    try clampedSource.connect(upstream)
    try upstream.connect(downstream)
    try downstream.connect(clamped.destination)
    clamped.destination.setChannelInterpretation(.discrete)
    let clampedBuffer = try await clamped.startRendering()
    #expect(try clampedBuffer.getChannelData(0)[0] == 1)
    #expect(try clampedBuffer.getChannelData(1)[0] == 0)
}

@MainActor
@Test func delayHistoryAdaptsWhenChannelLayoutChanges() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 2, length: 384, sampleRate: 48_000)
    let source = context.createConstantSource()
    let delay = try context.createDelay()
    try source.start()
    try source.stop(1.0 / 48_000)
    delay.delayTime.value = 256.0 / 48_000
    try source.connect(delay)
    try delay.connect(context.destination)
    context.destination.setChannelInterpretation(.discrete)

    let suspension = Task { try await context.suspend(at: 128.0 / 48_000) }
    await Task.yield()
    let rendering = Task { () throws -> ([Float], [Float]) in
        let buffer = try await context.startRendering()
        return (Array(try buffer.getChannelData(0)), Array(try buffer.getChannelData(1)))
    }
    try await suspension.value
    try delay.setChannelCount(2)
    try delay.setChannelCountMode(.explicit)
    try await context.resume()

    let (left, right) = try await rendering.value
    #expect(abs(left[256] - 1) < 0.001)
    #expect(abs(right[256] - 1) < 0.001)
}

@MainActor
@Test func delayHistoryUsesSpeakerRemixForSurroundLayout() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 6, length: 384, sampleRate: 48_000)
    let source = context.createConstantSource()
    let delay = try context.createDelay()
    try source.start()
    try source.stop(1.0 / 48_000)
    delay.delayTime.value = 256.0 / 48_000
    try source.connect(delay)
    try delay.connect(context.destination)
    context.destination.setChannelInterpretation(.discrete)

    let suspension = Task { try await context.suspend(at: 128.0 / 48_000) }
    await Task.yield()
    let rendering = Task { () throws -> [Float] in
        let buffer = try await context.startRendering()
        return try (0 ..< 6).map { try buffer.getChannelData(UInt32($0))[256] }
    }
    try await suspension.value
    try delay.setChannelCount(6)
    try delay.setChannelCountMode(.explicit)
    try await context.resume()

    let values = try await rendering.value
    for (channel, value) in values.enumerated() {
        #expect(abs(value - (channel == 2 ? 1 : 0)) < 0.001)
    }
}

@MainActor
@Test func delayAcceptsThirtyTwoDiscreteChannels() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 32, length: 128, sampleRate: 48_000)
    let source = context.createConstantSource()
    let delay = try DelayNode(context: context, options: DelayOptions(
        channelCount: 32, channelCountMode: .explicit, channelInterpretation: .discrete
    ))
    try source.start()
    try source.connect(delay)
    try delay.connect(context.destination)
    context.destination.setChannelInterpretation(.discrete)

    let buffer = try await context.startRendering()
    #expect(try buffer.getChannelData(0)[0] == 1)
    #expect(try buffer.getChannelData(31)[0] == 0)
}

@MainActor
@Test func feedbackConnectionChangeRetainsDelayHistory() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 384, sampleRate: 48_000)
    let source = context.createConstantSource()
    let delay = try context.createDelay()
    try source.start()
    try source.connect(delay)
    try delay.connect(context.destination)

    let suspension = Task { try await context.suspend(at: 128.0 / 48_000) }
    await Task.yield()
    let rendering = Task { () throws -> [Float] in
        let buffer = try await context.startRendering()
        return Array(try buffer.getChannelData(0))
    }
    try await suspension.value
    try delay.connect(delay)
    try await context.resume()

    let samples = try await rendering.value
    #expect(abs(samples[0] - 1) < 0.001)
    #expect(abs(samples[128] - 1) < 0.001)
    #expect(abs(samples[256] - 2) < 0.001)
}

@MainActor
@Test func delayedStereoTailKeepsItsChannelsUntilItFinishes() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 2, length: 512, sampleRate: 48_000)
    let source = context.createConstantSource()
    let upstream = try DelayNode(context: context, options: DelayOptions(
        channelCount: 2, channelCountMode: .explicit
    ))
    let delayed = try context.createDelay()
    delayed.delayTime.value = 256.0 / 48_000
    try source.start()
    try source.connect(upstream)
    try upstream.connect(delayed)
    try delayed.connect(context.destination)
    context.destination.setChannelInterpretation(.discrete)

    let suspension = Task { try await context.suspend(at: 128.0 / 48_000) }
    await Task.yield()
    let rendering = Task { () throws -> [Float] in
        let buffer = try await context.startRendering()
        return Array(try buffer.getChannelData(1))
    }
    try await suspension.value
    try upstream.setChannelCountMode(.max)
    try await context.resume()

    let right = try await rendering.value
    #expect(abs(right[256] - 1) < 0.001)
    #expect(abs(right[384]) < 0.001)
}

@MainActor
@Test func delayedOutputGainsChannelsWhenStereoInputReachesIt() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 2, length: 512, sampleRate: 48_000)
    let source = context.createConstantSource()
    let upstream = try context.createDelay()
    let delayed = try context.createDelay()
    delayed.delayTime.value = 300.0 / 48_000
    try source.start()
    try source.connect(upstream)
    try upstream.connect(delayed)
    try delayed.connect(context.destination)
    context.destination.setChannelInterpretation(.discrete)

    let suspension = Task { try await context.suspend(at: 128.0 / 48_000) }
    await Task.yield()
    let rendering = Task { () throws -> [Float] in
        let buffer = try await context.startRendering()
        return Array(try buffer.getChannelData(1))
    }
    try await suspension.value
    try upstream.setChannelCount(2)
    try upstream.setChannelCountMode(.explicit)
    try await context.resume()

    let right = try await rendering.value
    #expect(abs(right[256]) < 0.001)
    #expect(abs(right[384] - 1) < 0.001)
}
