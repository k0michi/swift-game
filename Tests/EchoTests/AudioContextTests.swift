@testable import Echo
import Testing

private final class ManualAudioBackend: AudioOutputBackend, @unchecked Sendable {
    let sampleRate: Float
    let channelCount: UInt32
    var failStart = false
    private var render: (@Sendable (UnsafeMutableBufferPointer<Float>) -> Void)?
    private var onError: (@Sendable () -> Void)?

    init(sampleRate: Float = 48_000, channelCount: UInt32 = 2) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }

    func start(
        render: @escaping @Sendable (UnsafeMutableBufferPointer<Float>) -> Void,
        onError: @escaping @Sendable () -> Void
    ) throws {
        if failStart { throw WebAudioError.notSupported }
        self.render = render
        self.onError = onError
    }

    func stop() throws {
        render = nil
        onError = nil
    }

    func failWhileRunning() { onError?() }

    func pull(frames: Int) -> [Float] {
        var samples = [Float](repeating: 0, count: frames * Int(channelCount))
        samples.withUnsafeMutableBufferPointer { render?($0) }
        return samples
    }
}

@MainActor
@Test func realtimeContextRendersInterleavedAudioAcrossPartialPulls() async throws {
    let backend = ManualAudioBackend()
    let context = try AudioContext(backend: backend)
    let source = context.createConstantSource()
    try source.start()
    try source.connect(context.destination)
    try await context.resume()

    let first = backend.pull(frames: 64)
    #expect(first.allSatisfy { $0 == 1 })
    #expect(context.currentTime == 128.0 / 48_000)

    source.offset.value = 0.5
    let remainder = backend.pull(frames: 64)
    let next = backend.pull(frames: 64)
    #expect(remainder.allSatisfy { $0 == 1 })
    #expect(next.allSatisfy { $0 == 0.5 })

    try await context.suspend()
    #expect(context.state == .suspended)
    try await context.resume()
    #expect(backend.pull(frames: 64).allSatisfy { $0 == 0.5 })
    try await context.close()
    #expect(context.state == .closed)
}

@MainActor
@Test func realtimeBackendStartFailureLeavesContextSuspended() async throws {
    let backend = ManualAudioBackend()
    backend.failStart = true
    let context = try AudioContext(backend: backend)
    do {
        try await context.resume()
        Issue.record("Backend start failure was ignored")
    } catch {
        #expect(error as? WebAudioError == .notSupported)
    }
    #expect(context.state == .suspended)
    #expect(context.currentTime == 0)
}

@MainActor
@Test func realtimeBackendFailureNotifiesAndSuspendsContext() async throws {
    let backend = ManualAudioBackend()
    let context = try AudioContext(backend: backend)
    var events: [String] = []
    context.onerror = { events.append("error") }
    context.onstatechange = { events.append($0.rawValue) }
    try await context.resume()

    backend.failWhileRunning()
    for _ in 0 ..< 100 where context.state == .running {
        try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(context.state == .suspended)
    #expect(events == ["running", "error", "suspended"])
    try await context.close()
}

@MainActor
@Test func graphPreparationFailureNotifiesContext() async throws {
    final class UnsupportedNode: AudioNode {
        init(context: BaseAudioContext) {
            super.init(
                context: context,
                numberOfInputs: 0,
                numberOfOutputs: 1,
                channelCount: 1,
                channelCountMode: .max,
                channelInterpretation: .speakers
            )
        }
    }

    let backend = ManualAudioBackend()
    let context = try AudioContext(backend: backend)
    var events: [String] = []
    context.onerror = { events.append("error") }
    context.onstatechange = { events.append($0.rawValue) }
    try await context.resume()

    try UnsupportedNode(context: context).connect(context.destination)

    #expect(context.state == .closed)
    #expect(events == ["running", "error", "closed"])
}

@MainActor
@Test func realtimeDestinationMixesIntoPhysicalOutputChannels() async throws {
    let backend = ManualAudioBackend()
    let context = try AudioContext(backend: backend)
    let source = context.createConstantSource()
    try source.start()
    try source.connect(context.destination)
    try context.destination.setChannelCount(1)
    context.destination.setChannelInterpretation(.discrete)
    let plan = try context.graph.makeRenderPlan(destination: context.destination, frameCount: 128)
    #expect(plan.destinationChannelCount == 2)
    try await context.resume()

    let discrete = backend.pull(frames: 128)
    #expect(discrete[0] == 1)
    #expect(discrete[1] == 0)

    context.destination.setChannelInterpretation(.speakers)
    let speakers = backend.pull(frames: 128)
    #expect(speakers[0] == 1)
    #expect(speakers[1] == 1)
    try await context.close()
}

@MainActor
@Test func realtimePlanReplacementRetainsDelayHistory() async throws {
    let backend = ManualAudioBackend(channelCount: 1)
    let context = try AudioContext(backend: backend)
    let source = context.createConstantSource()
    let delay = try context.createDelay()
    try source.start()
    try source.stop(1.0 / 48_000)
    delay.delayTime.value = 128.0 / 48_000
    try source.connect(delay)
    try delay.connect(context.destination)
    try await context.resume()

    #expect(backend.pull(frames: 128).allSatisfy { abs($0) < 0.001 })
    delay.delayTime.value = 256.0 / 48_000
    #expect(backend.pull(frames: 128).allSatisfy { abs($0) < 0.001 })
    let third = backend.pull(frames: 128)
    #expect(abs(third[0] - 1) < 0.001)
    try await context.close()
}

@MainActor
@Test func mediaStreamSourceSelectsFirstAudioTrackAndRendersChannels() async throws {
    let backend = ManualAudioBackend(channelCount: 2)
    let context = try AudioContext(
        options: AudioContextOptions(renderSizeHint: .frameCount(4)),
        backend: backend
    )
    let later = try MediaStreamTrack(id: "z", sampleRate: 48_000, channelCount: 1)
    let selected = try MediaStreamTrack(id: "a", sampleRate: 48_000, channelCount: 2)
    let stream = MediaStream(tracks: [later, selected])
    let source = try context.createMediaStreamSource(stream)
    try source.connect(context.destination)
    try await context.resume()

    _ = [Float](arrayLiteral: 0.25, 0.75, 0.5, 1, 0.75, 0.25, 1, 0.5)
        .withUnsafeBufferPointer { selected.appendInterleaved($0) }
    _ = [Float](repeating: 1, count: 4)
        .withUnsafeBufferPointer { later.appendInterleaved($0) }
    #expect(source.mediaStream === stream)
    #expect(backend.pull(frames: 4) == [0.25, 0.75, 0.5, 1, 0.75, 0.25, 1, 0.5])

    selected.stop()
    let endedOutput = AudioRenderQuantum(channelCapacity: 2, frameCount: 4, channelCount: 2)
    source.renderState.render(into: endedOutput)
    #expect(endedOutput.channelCount == 1)
    #expect(backend.pull(frames: 4).allSatisfy { $0 == 0 })
    try await context.close()
}

@MainActor
@Test func mediaStreamTrackSelectionUsesUTF16CodeUnitOrder() throws {
    let backend = ManualAudioBackend(channelCount: 1)
    let context = try AudioContext(backend: backend)
    let supplementary = try MediaStreamTrack(id: "\u{10000}", sampleRate: 48_000, channelCount: 1)
    let basic = try MediaStreamTrack(id: "\u{E000}", sampleRate: 48_000, channelCount: 1)
    let source = try context.createMediaStreamSource(MediaStream(tracks: [basic, supplementary]))
    #expect(source.renderState.track === supplementary)
}

@MainActor
@Test func mediaStreamSourceResamplesAndRejectsEmptyStream() async throws {
    let backend = ManualAudioBackend(channelCount: 1)
    let context = try AudioContext(
        options: AudioContextOptions(renderSizeHint: .frameCount(4)),
        backend: backend
    )
    #expect(throws: WebAudioError.invalidState) {
        try context.createMediaStreamSource(MediaStream(tracks: []))
    }
    let track = try MediaStreamTrack(id: "mic", sampleRate: 24_000, channelCount: 1)
    let source = try context.createMediaStreamSource(MediaStream(tracks: [track]))
    try source.connect(context.destination)
    try await context.resume()
    _ = [Float](arrayLiteral: 0, 1, 0).withUnsafeBufferPointer { track.appendInterleaved($0) }

    #expect(backend.pull(frames: 4) == [0, 0.5, 1, 0.5])
    try await context.close()
}
