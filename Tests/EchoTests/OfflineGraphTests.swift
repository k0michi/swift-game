@testable import Echo
import Foundation
import Testing

@MainActor
@Test func connectedConstantSourceRendersThroughDestination() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 2, length: 256, sampleRate: 48_000)
    let source = context.createConstantSource()
    source.offset.value = 0.25
    try source.start(64.0 / 48_000)
    try source.stop(192.0 / 48_000)
    try source.connect(context.destination)

    let buffer = try await context.startRendering()
    for channel in 0 ..< 2 {
        let samples = try buffer.getChannelData(UInt32(channel))
        #expect(samples[0] == 0)
        #expect(samples[63] == 0)
        #expect(samples[64] == 0.25)
        #expect(samples[191] == 0.25)
        #expect(samples[192] == 0)
    }
}

@MainActor
@Test func duplicateConnectionsAreIgnoredAndSourcesSum() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    let first = context.createConstantSource()
    let second = context.createConstantSource()
    first.offset.value = 0.25
    second.offset.value = 0.5
    try first.start()
    try second.start()
    try first.connect(context.destination)
    try first.connect(context.destination)
    try second.connect(context.destination)

    let buffer = try await context.startRendering()
    #expect(try buffer.getChannelData(0)[0] == 0.75)
}

@MainActor
@Test func disconnectRemovesSourceFromOfflineGraph() async throws {
    let context = try OfflineAudioContext(options: OfflineAudioContextOptions(sampleRate: 48_000))
    let source = context.createConstantSource()
    try source.start()
    try source.connect(context.destination)
    source.disconnect()

    let buffer = try await context.startRendering()
    #expect(try buffer.getChannelData(0).allSatisfy { $0 == 0 })
}

@MainActor
@Test func chunkedRenderingPreservesSchedulingAndConnectionChanges() async throws {
    let context = try OfflineAudioContext(options: OfflineAudioContextOptions(
        sampleRate: 48_000,
        renderSizeHint: .frameCount(64)
    ))
    let source = context.createConstantSource()
    source.offset.value = 0.5
    try source.start(80.0 / 48_000)
    try source.connect(context.destination)

    let first = try await context.startRendering()
    let second = try await context.startRendering()
    source.disconnect()
    let third = try await context.startRendering()

    #expect(try first.getChannelData(0).allSatisfy { $0 == 0 })
    #expect(try second.getChannelData(0)[15] == 0)
    #expect(try second.getChannelData(0)[16] == 0.5)
    #expect(try third.getChannelData(0).allSatisfy { $0 == 0 })
}

@MainActor
@Test func connectionsValidateContextAndPortIndices() throws {
    let first = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    let second = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    let source = first.createConstantSource()

    #expect(throws: WebAudioError.invalidAccess) {
        try source.connect(second.destination)
    }
    #expect(throws: WebAudioError.indexSize) {
        try source.connect(first.destination, output: 1)
    }
    #expect(throws: WebAudioError.indexSize) {
        try source.connect(first.destination, input: 1)
    }
}

@MainActor
@Test func cycleWithoutDelayIsMutedRatherThanRejected() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    let source = context.createConstantSource()
    try source.start()
    try source.connect(context.destination)
    try context.destination.connect(context.destination)

    let buffer = try await context.startRendering()

    #expect(try buffer.getChannelData(0).allSatisfy { $0 == 0 })
}

@MainActor
@Test func audioParamInputModulatesConstantSource() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    let modulator = context.createConstantSource()
    let source = context.createConstantSource()
    modulator.offset.value = 0.25
    source.offset.value = 0.5
    try modulator.start()
    try source.start()
    try modulator.connect(source.offset)
    try source.connect(context.destination)

    let buffer = try await context.startRendering()

    #expect(try buffer.getChannelData(0)[0] == 0.75)
}

@MainActor
@Test func audioParamSelfFeedbackMutesCyclicNode() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    let source = context.createConstantSource()
    try source.start()
    try source.connect(source.offset)
    try source.connect(context.destination)

    let buffer = try await context.startRendering()

    #expect(try buffer.getChannelData(0).allSatisfy { $0 == 0 })
}

@MainActor
@Test func audioParamConnectionCanBeRemovedBetweenChunks() async throws {
    let context = try OfflineAudioContext(options: OfflineAudioContextOptions(sampleRate: 48_000))
    let modulator = context.createConstantSource()
    let source = context.createConstantSource()
    modulator.offset.value = 0.25
    source.offset.value = 0.5
    try modulator.start()
    try source.start()
    try modulator.connect(source.offset)
    try source.connect(context.destination)

    let first = try await context.startRendering()
    try modulator.disconnect(source.offset)
    let second = try await context.startRendering()

    #expect(try first.getChannelData(0)[0] == 0.75)
    #expect(try second.getChannelData(0)[0] == 0.5)
}

@MainActor
@Test func renderPlanDoesNotReadMutableControlObjects() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    let source = context.createConstantSource()
    source.offset.value = 0.25
    try source.start()
    try source.connect(context.destination)

    let plan = try context.graph.makeRenderPlan(destination: context.destination, frameCount: 128)
    let buffer = try context.createBuffer(numberOfChannels: 1, length: 128, sampleRate: 48_000)
    source.offset.value = 0.75

    let result = try await OfflineRenderWorker.render(
        controlQueue: RenderControlQueue(initialPlan: plan),
        into: OfflineRenderBuffer(value: buffer),
        from: 0,
        currentFrame: context.currentFrame
    )

    #expect(result.ranOnMainThread == false)
    #expect(try result.buffer.getChannelData(0)[0] == 0.25)
}

@MainActor
@Test func controlMessagesApplyAtTheNextRenderQuantum() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 256, sampleRate: 48_000)
    let source = context.createConstantSource()
    source.offset.value = 0.25
    try source.start()
    try source.connect(context.destination)

    let initialPlan = try context.graph.makeRenderPlan(destination: context.destination, frameCount: 128)
    let queue = RenderControlQueue(initialPlan: initialPlan)
    let renderBuffer = OfflineRenderBuffer(value: try context.createBuffer(
        numberOfChannels: 1,
        length: 256,
        sampleRate: 48_000
    ))
    let reachedBoundary = DispatchSemaphore(value: 0)
    let resumeRendering = DispatchSemaphore(value: 0)
    let currentFrame = context.currentFrame

    let renderTask = Task.detached {
        try await OfflineRenderWorker.render(
            controlQueue: queue,
            into: renderBuffer,
            from: 0,
            currentFrame: currentFrame,
            beforeQuantum: { frame in
                if frame == 128 {
                    reachedBoundary.signal()
                    resumeRendering.wait()
                }
            }
        )
    }

    let didReachBoundary = await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            continuation.resume(returning: reachedBoundary.wait(timeout: .now() + 5) == .success)
        }
    }
    guard didReachBoundary else {
        resumeRendering.signal()
        _ = try await renderTask.value
        Issue.record("Rendering did not reach the second quantum")
        return
    }
    source.offset.value = 0.75
    let replacement = try context.graph.makeRenderPlan(destination: context.destination, frameCount: 128)
    queue.enqueue(replacement)
    resumeRendering.signal()

    let result = try await renderTask.value
    let samples = try result.buffer.getChannelData(0)
    #expect(samples[0] == 0.25)
    #expect(samples[127] == 0.25)
    #expect(samples[128] == 0.75)
    #expect(samples[255] == 0.75)
}
