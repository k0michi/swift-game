@testable import Echo
import Testing

private func timeline(_ events: [AudioParamTimeline.Event]) throws -> AudioParamTimeline {
    var timeline = AudioParamTimeline(defaultValue: 0.5, minValue: -10, maxValue: 10, sampleRate: 100, automationRate: .aRate)
    for event in events {
        if case let .curve(values, duration, _) = event.kind {
            try timeline.insertCurve(values, at: event.time, duration: duration)
        } else {
            try timeline.insert(event)
        }
    }
    return timeline
}

// Each with an event running at time 2 or ending just before it.
private let histories: [[AudioParamTimeline.Event]] = [
    [.init(time: 0, kind: .set(1)), .init(time: 1, kind: .linearRamp(3)), .init(time: 4, kind: .linearRamp(-1))],
    [.init(time: 0.5, kind: .set(2)), .init(time: 1, kind: .exponentialRamp(4)), .init(time: 1.5, kind: .set(1))],
    [.init(time: 0, kind: .set(1)), .init(time: 1, kind: .target(3, timeConstant: 0.5)),
     .init(time: 3, kind: .linearRamp(0))],
    [.init(time: 0, kind: .linearRamp(2)), .init(time: 1, kind: .curve([0, 4, 1], duration: 2, cutoff: nil))],
    [.init(time: 0.2, kind: .set(-2)), .init(time: 0.5, kind: .curve([1, 2], duration: 1, cutoff: nil)),
     .init(time: 1.8, kind: .target(5, timeConstant: 0.2))],
    [.init(time: 0, kind: .set(1)), .init(time: 2, kind: .set(3))],
]

// Discarding the past keeps every later value, and what cancelling from
// then on leaves, and keeps no more than two events of it.
@Test(arguments: histories)
func discardingThePastKeepsLaterValues(_ events: [AudioParamTimeline.Event]) throws {
    let now = 2.0
    let original = try timeline(events)
    var discarded = original
    discarded.discardEvents(before: now)

    #expect(discarded.events.count(where: { $0.time < now }) <= 2)
    let times = stride(from: now, through: 6, by: 0.05)
    for time in times {
        #expect(abs(discarded.intrinsicValue(at: time) - original.intrinsicValue(at: time)) < 1e-5, "at \(time)")
    }
    for cancelTime in [now, 2.5, 4] {
        var cancelled = original
        cancelled.cancel(from: cancelTime)
        var discardedThenCancelled = discarded
        discardedThenCancelled.cancel(from: cancelTime)
        var held = original
        held.cancelAndHold(at: cancelTime)
        var discardedThenHeld = discarded
        discardedThenHeld.cancelAndHold(at: cancelTime)
        for time in times {
            #expect(abs(discardedThenCancelled.intrinsicValue(at: time) - cancelled.intrinsicValue(at: time)) < 1e-5,
                    "cancelled from \(cancelTime), at \(time)")
            #expect(abs(discardedThenHeld.intrinsicValue(at: time) - held.intrinsicValue(at: time)) < 1e-5,
                    "held at \(cancelTime), at \(time)")
        }
    }
}

// A parameter set again and again holds only its latest values.
@MainActor
@Test func settingAParameterRepeatedlyKeepsItsTimelineShort() async throws {
    let context = try OfflineAudioContext(numberOfChannels: 1, length: 128 * 64, sampleRate: 48_000)
    let gain = context.createGain()
    try context.createConstantSource().connect(gain)
    try gain.connect(context.destination)
    var scheduled = 0
    var settings = 0
    for quantum in 1 ..< 64 {
        Task {
            scheduled += 1
            // Rounded up to the quantum.
            try await context.suspend(at: Double(quantum * 128 - 64) / 48_000)
            gain.gain.value = Float(quantum % 2)
            settings += 1
            try await context.resume()
        }
    }
    // Until every suspension is scheduled, which suspend does before it
    // first waits.
    while scheduled < 63 { await Task.yield() }
    _ = try await context.startRendering()
    #expect(settings == 63)
    #expect(gain.gain.handler.renderTimeline.events.count <= 2)
}
