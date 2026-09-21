import Echo
import Testing

@MainActor
@Test func offlineContextCreatesItsDestinationFromOptions() throws {
    let context = try OfflineAudioContext(
        numberOfChannels: 2,
        length: 256,
        sampleRate: 48_000
    )

    #expect(context.state == .suspended)
    #expect(context.currentTime == 0)
    #expect(context.renderQuantumSize == 128)
    #expect(context.destination.context === context)
    #expect(context.destination.numberOfInputs == 1)
    #expect(context.destination.numberOfOutputs == 1)
    #expect(context.destination.channelCount == 2)
    #expect(context.destination.channelCountMode == .explicit)
    #expect(context.destination.channelInterpretation == .speakers)
    #expect(context.destination.maxChannelCount == 2)
}

@MainActor
@Test func offlineDestinationChannelCountIsImmutable() throws {
    let context = try OfflineAudioContext(numberOfChannels: 2, length: 128, sampleRate: 48_000)

    try context.destination.setChannelCount(2)
    #expect(throws: WebAudioError.invalidState) {
        try context.destination.setChannelCount(1)
    }
    try context.destination.setChannelCountMode(.explicit)
    #expect(throws: WebAudioError.invalidState) {
        try context.destination.setChannelCountMode(.max)
    }
}

@MainActor
@Test func offlineRenderingProducesQuantumAlignedSilence() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 2, length: 130, sampleRate: 48_000)
    var states: [AudioContextState] = []
    var completedBuffer: AudioBuffer?
    context.onstatechange = { states.append($0) }
    context.oncomplete = { completedBuffer = $0.renderedBuffer }

    let buffer = try await context.startRendering()

    #expect(buffer.length == 256)
    #expect(try buffer.getChannelData(0).allSatisfy { $0 == 0 })
    #expect(context.currentTime == Double(256) / 48_000)
    #expect(context.state == .closed)
    #expect(states == [.running, .closed])
    #expect(completedBuffer === buffer)
}

@MainActor
@Test func undefinedLengthOfflineRenderingUsesChunks() async throws {
    let context = try OfflineAudioContext(options: OfflineAudioContextOptions(
        numberOfChannels: 1,
        sampleRate: 48_000
    ))

    let first = try await context.startRendering()
    let second = try await context.startRendering(chunkSize: 129)

    #expect(first.length == 128)
    #expect(second.length == 256)
    #expect(context.state == .suspended)
    #expect(context.currentTime == Double(384) / 48_000)
}

@MainActor
@Test func offlineContextValidatesConstructionAndState() async throws {
    #expect(throws: WebAudioError.notSupported) {
        try OfflineAudioContext(numberOfChannels: 0, length: 128, sampleRate: 48_000)
    }
    #expect(throws: WebAudioError.notSupported) {
        try OfflineAudioContext(options: OfflineAudioContextOptions(
            sampleRate: 48_000,
            renderSizeHint: .frameCount(0)
        ))
    }

    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    _ = try await context.startRendering()
    do {
        _ = try await context.startRendering()
        Issue.record("Expected startRendering() to reject a closed context")
    } catch let error as WebAudioError {
        #expect(error == .invalidState)
    }
}

@MainActor
@Test func offlineSuspensionStopsAtQuantumBoundaryAndResumesWithGraphChanges() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 256, sampleRate: 48_000)
    let source = context.createConstantSource()
    source.offset.value = 0.25
    try source.start()
    try source.connect(context.destination)

    let suspension = Task { try await context.suspend(at: 127.0 / 48_000) }
    await Task.yield()
    let rendering = Task { () throws -> [Float] in
        let buffer = try await context.startRendering()
        return Array(try buffer.getChannelData(0))
    }
    try await suspension.value

    #expect(context.state == .suspended)
    #expect(context.currentTime == 128.0 / 48_000)
    source.offset.value = 0.75
    try await context.resume()
    let samples = try await rendering.value
    #expect(samples[0] == 0.25)
    #expect(samples[127] == 0.25)
    #expect(samples[128] == 0.75)
    #expect(samples[255] == 0.75)
}

@MainActor
@Test func closingSuspendedOfflineRenderUnblocksWorker() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 256, sampleRate: 48_000)
    let suspension = Task { try await context.suspend(at: 128.0 / 48_000) }
    await Task.yield()
    let rendering = Task { () throws -> Void in
        _ = try await context.startRendering()
    }
    try await suspension.value

    try await context.close()
    #expect(context.state == .closed)
    await #expect(throws: WebAudioError.invalidState) {
        _ = try await rendering.value
    }
    await #expect(throws: WebAudioError.invalidState) {
        try await context.resume()
    }
}

@MainActor
@Test func closeRejectsFutureSuspensionsAndWaitsForRenderExit() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 384, sampleRate: 48_000)
    let first = Task { try await context.suspend(at: 128.0 / 48_000) }
    let future = Task { try await context.suspend(at: 256.0 / 48_000) }
    await Task.yield()
    let rendering = Task { () throws -> Void in
        _ = try await context.startRendering()
    }
    try await first.value

    try await context.close()

    #expect(context.state == .closed)
    await #expect(throws: WebAudioError.invalidState) {
        try await future.value
    }
    await #expect(throws: WebAudioError.invalidState) {
        try await rendering.value
    }
}

@MainActor
@Test func offlineSuspensionRejectsInvalidAndDuplicateFrames() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 256, sampleRate: 48_000)
    await #expect(throws: WebAudioError.invalidState) {
        try await context.suspend(at: 0)
    }
    await #expect(throws: WebAudioError.invalidState) {
        try await context.suspend(at: .nan)
    }
    await #expect(throws: WebAudioError.invalidState) {
        try await context.suspend(at: 256.0 / 48_000)
    }

    let first = Task { try await context.suspend(at: 128.0 / 48_000) }
    await Task.yield()
    await #expect(throws: WebAudioError.invalidState) {
        try await context.suspend(at: 127.0 / 48_000)
    }
    try await context.close()
    await #expect(throws: WebAudioError.invalidState) {
        try await first.value
    }
}
