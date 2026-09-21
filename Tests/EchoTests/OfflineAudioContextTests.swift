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
    #expect(throws: WebAudioError.notSupported) {
        try context.destination.setChannelCount(1)
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
