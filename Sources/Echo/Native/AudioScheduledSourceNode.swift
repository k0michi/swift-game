// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
import Atomics

// What a source shares with the rendering thread to say that it has ended.
final class EndedSignal: Sendable {
    private let ended = ManagedAtomic(false)

    var hasEnded: Bool { ended.load(ordering: .acquiring) }

    func signal() {
        ended.store(true, ordering: .releasing)
    }
}

// The sources that a start and a stop time schedule. The context keeps a
// started source until it ends, then calls onended.
@MainActor
public class AudioScheduledSourceNode: AudioNode {
    public var onended: (() -> Void)?

    // [[source started]] is whether there is a start time.
    private(set) var startTime: Double?
    private(set) var stopTime: Double?
    let endedSignal = EndedSignal()

    public func start(_ when: Double = 0) throws {
        try scheduleStart(when)
    }

    // If called again, the last time applies, unless the source has already
    // stopped.
    public func stop(_ when: Double = 0) throws {
        guard startTime != nil else { throw WebAudioError.invalidState }
        stopTime = try scheduledTime(when)
        context.graphDidChange()
    }

    // Schedules the start once its subclass has checked its own arguments.
    func scheduleStart(_ when: Double) throws {
        guard startTime == nil else { throw WebAudioError.invalidState }
        startTime = try scheduledTime(when)
        context.sourceDidStart(self)
        context.graphDidChange()
    }

    // The time exactly, or now for a time already past. A time is a double,
    // which takes only finite values.
    func scheduledTime(_ when: Double) throws -> Double {
        guard when.isFinite, when >= 0 else { throw WebAudioError.rangeError }
        return max(when, context.currentTime)
    }
}
#endif
