@testable import Echo
import Testing

@MainActor
private final class UnsupportedAudioNode: AudioNode {
    init(context: BaseAudioContext) {
        super.init(
            context: context, numberOfInputs: 0, numberOfOutputs: 1,
            channelCount: 1, channelCountMode: .max, channelInterpretation: .speakers
        )
    }
}

@MainActor
@Test func graphPreparationFailureClosesActiveOfflineRender() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 384, sampleRate: 48_000)
    let suspension = Task { try await context.suspend(at: 128.0 / 48_000) }
    await Task.yield()
    let rendering = Task { () throws -> Void in
        _ = try await context.startRendering()
    }
    try await suspension.value
    let unsupported = UnsupportedAudioNode(context: context)
    try unsupported.connect(context.destination)

    do {
        try await rendering.value
        Issue.record("Render did not reject unsupported graph")
    } catch {
        #expect(error as? WebAudioError == .notSupported)
    }
    #expect(context.state == .closed)
    #expect(context.currentTime == 128.0 / 48_000)
}
