#if os(Emscripten)
import Echo

let sampleRate: Float = 48_000

@MainActor
let tests: [(String, @MainActor () async throws -> Void)] = [
    ("testConstantSource", testConstantSource),
    ("testRamp", testRamp),
    ("testDelay", testDelay),
    ("testChannelSettings", testChannelSettings),
    ("testErrors", testErrors),
    ("testSuspendAndResume", testSuspendAndResume),
    ("testStateChanges", testStateChanges),
    ("testAudioContext", testAudioContext),
]

@MainActor
func render(length: UInt32, channels: UInt32 = 1, _ build: (OfflineAudioContext) throws -> Void) async throws -> AudioBuffer {
    let context = try OfflineAudioContext(numberOfChannels: channels, length: length, sampleRate: sampleRate)
    try build(context)
    return try await context.startRendering()
}

@MainActor
func testConstantSource() async throws {
    var completed = false
    let context = try OfflineAudioContext(numberOfChannels: 2, length: 256, sampleRate: sampleRate)
    context.oncomplete = { _ in completed = true }
    let source = context.createConstantSource()
    expect(source.offset.defaultValue == 1, "offset defaults to 1")
    source.offset.value = 0.5
    try source.connect(context.destination)
    try source.start()
    let buffer = try await context.startRendering()
    expect(completed, "oncomplete is called")
    expect(buffer.numberOfChannels == 2 && buffer.length == 256 && buffer.sampleRate == sampleRate, "buffer shape")
    for channel in 0 ..< buffer.numberOfChannels {
        let data = try buffer.getChannelData(channel)
        expect(data.allSatisfy { isClose($0, 0.5) }, "channel \(channel) is 0.5 throughout")
    }
}

@MainActor
func testRamp() async throws {
    let buffer = try await render(length: 256) { context in
        let source = context.createConstantSource()
        try source.offset.setValueAtTime(0, startTime: 0)
        try source.offset.linearRampToValueAtTime(1, endTime: 255 / Double(sampleRate))
        try source.connect(context.destination)
        try source.start()
    }
    let data = try buffer.getChannelData(0)
    for frame in [0, 64, 128, 255] {
        expect(isClose(data[frame], Float(frame) / 255), "ramp at \(frame) is \(data[frame])")
    }
}

@MainActor
func testDelay() async throws {
    let buffer = try await render(length: 256) { context in
        let source = context.createConstantSource()
        let delay = try context.createDelay(0.1)
        delay.delayTime.value = 64 / sampleRate
        expect(delay.maxDelayTime == 0.1, "maxDelayTime")
        try source.connect(delay).connect(context.destination)
        try source.start()
    }
    let data = try buffer.getChannelData(0)
    expect(data[0 ..< 64].allSatisfy { $0 == 0 }, "silence before the delay")
    expect(data[64 ..< 256].allSatisfy { isClose($0, 1) }, "the source after the delay")
}

@MainActor
func testChannelSettings() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 2, length: 128, sampleRate: sampleRate)
    let delay = try DelayNode(context: context, options: DelayOptions(channelCount: 1, channelCountMode: .explicit))
    expect(delay.channelCount == 1 && delay.channelCountMode == .explicit, "options are applied")
    try delay.setChannelCount(2)
    try delay.setChannelCountMode(.clampedMax)
    delay.setChannelInterpretation(.discrete)
    expect(
        delay.channelCount == 2 && delay.channelCountMode == .clampedMax && delay.channelInterpretation == .discrete,
        "setters are applied"
    )
    expect(delay.numberOfInputs == 1 && delay.numberOfOutputs == 1, "delay inputs and outputs")
    expect(context.destination.maxChannelCount == 2, "destination maxChannelCount")
    expect(context.sampleRate == sampleRate && context.renderQuantumSize == 128, "context properties")
}

@MainActor
func testErrors() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: sampleRate)
    let source = context.createConstantSource()
    let other = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: sampleRate)
    expect(.indexSize, "connect to an output that does not exist") {
        try source.connect(context.destination, output: 1)
    }
    expect(.invalidAccess, "connect across contexts") {
        try source.connect(other.destination)
    }
    expect(.invalidAccess, "disconnect from a node that is not connected") {
        try source.disconnect(context.destination)
    }
    expect(.notSupported, "a delay of 180 s or more") {
        _ = try context.createDelay(200)
    }
    expect(.rangeError, "an exponential ramp to 0") {
        try source.offset.exponentialRampToValueAtTime(0, endTime: 1)
    }
    try source.start()
    expect(.invalidState, "start twice") {
        try source.start()
    }
    expect(.notSupported, "an offline context without a length") {
        _ = try OfflineAudioContext(options: OfflineAudioContextOptions(sampleRate: sampleRate))
    }
}

@MainActor
func testSuspendAndResume() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 512, sampleRate: sampleRate)
    let source = context.createConstantSource()
    try source.connect(context.destination)
    try source.start()
    let rendered = Rendered()
    let rendering = Task { @MainActor in rendered.buffer = try await context.startRendering() }
    try await context.suspend(at: 256 / Double(sampleRate))
    expect(context.state == .suspended, "suspended at the time")
    source.offset.value = 0.25
    try await context.resume()
    try await rendering.value
    let data = try rendered.buffer!.getChannelData(0)
    expect(data[0 ..< 256].allSatisfy { isClose($0, 1) }, "before the suspension")
    expect(data[256 ..< 512].allSatisfy { isClose($0, 0.25) }, "after the change at the suspension")
}

@MainActor
private final class Rendered {
    var buffer: AudioBuffer?
}

@MainActor
func testStateChanges() async throws {
    var states: [AudioContextState] = []
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: sampleRate)
    context.onstatechange = { states.append($0) }
    _ = try await context.startRendering()
    // The browser dispatches the closing statechange after resolving.
    await nextTask()
    expect(states.first == .running && states.last == .closed, "states: \(states)")
}

@MainActor
func testAudioContext() async throws {
    let context = try AudioContext()
    expect(context.sampleRate > 0, "sampleRate")
    expect(context.destination.maxChannelCount >= 1, "maxChannelCount")
    try await context.resume()
    expect(context.state == .running, "running after resume: \(context.state)")
    try await context.close()
    expect(context.state == .closed, "closed")
    do {
        try await context.resume()
        fail("resume after close: no error")
    } catch let error as WebAudioError {
        expect(error == .invalidState, "resume after close: \(error)")
    }
}

@MainActor
func nextTask() async {
    try? await Task.sleep(for: .milliseconds(10))
}
#endif
