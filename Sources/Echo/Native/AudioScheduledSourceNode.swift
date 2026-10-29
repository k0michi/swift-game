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

// What a node with a tail-time shares with the rendering thread to say
// whether it may still sound: whether sound has gone into or come out of it
// within its tail, as long as what went in can take to come out.
final class SoundingSignal: @unchecked Sendable {
    private let sounding = ManagedAtomic(false)
    private let tailFrames: Int
    // Frames since sound last went in or came out, which only the rendering
    // thread touches.
    private var quietFrames = Int.max / 2

    init(tailFrames: Int = 0) {
        self.tailFrames = tailFrames
    }

    var isSounding: Bool { sounding.load(ordering: .acquiring) }

    func update(input: AudioRenderQuantum?, output: AudioRenderQuantum) {
        if Self.hasSound(output) || input.map(Self.hasSound) == true {
            quietFrames = 0
        } else {
            quietFrames += output.frameCount
        }
        sounding.store(quietFrames <= tailFrames, ordering: .releasing)
    }

    // Sound is any sample of at least 2^-126, the threshold the
    // specification gives for a DelayNode in a cycle.
    private static func hasSound(_ quantum: AudioRenderQuantum) -> Bool {
        (0 ..< quantum.channelCount).contains { channel in
            quantum.channelData(channel).contains { abs($0) >= .leastNormalMagnitude }
        }
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
