@testable import Echo
import Testing

@MainActor
@Test func renderTargetRejectsInvalidOutputShapeBeforeStartingWorker() throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    let plan = try context.graph.makeRenderPlan(destination: context.destination, frameCount: 128)
    let unaligned = try context.createBuffer(numberOfChannels: 1, length: 129, sampleRate: 48_000)
    let wrongChannels = try context.createBuffer(numberOfChannels: 2, length: 128, sampleRate: 48_000)

    #expect(throws: WebAudioError.notSupported) {
        try OfflineRenderTarget(buffer: unaligned, plan: plan)
    }
    #expect(throws: WebAudioError.notSupported) {
        try OfflineRenderTarget(buffer: wrongChannels, plan: plan)
    }
}

@MainActor
@Test func incompatiblePlanReplacementFailsBeforeWritingOutput() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    let initial = try context.graph.makeRenderPlan(destination: context.destination, frameCount: 128)
    let replacement = try context.graph.makeRenderPlan(destination: context.destination, frameCount: 64)
    let queue = RenderControlQueue(initialPlan: initial)
    queue.enqueue(replacement)
    let buffer = try context.createBuffer(numberOfChannels: 1, length: 128, sampleRate: 48_000)

    do {
        _ = try await OfflineRenderWorker.render(
            controlQueue: queue, into: OfflineRenderBuffer(value: buffer),
            from: 0, currentFrame: context.currentFrame
        )
        Issue.record("Incompatible render plan was accepted")
    } catch {
        #expect(error as? WebAudioError == .notSupported)
    }
    #expect(context.currentTime == 0)
    #expect(try buffer.getChannelData(0).allSatisfy { $0 == 0 })
}
