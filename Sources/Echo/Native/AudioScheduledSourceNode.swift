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

// The sources that a start and a stop time schedule. A started source plays
// on its own until it ends, which keeps it in its context; then the context
// calls its onended.
@MainActor
class AudioScheduledSourceHandler: AudioHandler {
    var onended: (() -> Void)?

    // [[source started]] is whether there is a start time.
    private(set) var startTime: Double?
    private(set) var stopTime: Double?
    let endedSignal = EndedSignal()
    // Whether onended has been called for the end.
    var endedIsDispatched = false

    override var playsOnItsOwn: Bool { startTime != nil && !endedSignal.hasEnded }

    func start(_ when: Double) throws {
        try scheduleStart(when)
    }

    // If called again, the last time applies, unless the source has already
    // stopped.
    func stop(_ when: Double) throws {
        guard startTime != nil else { throw WebAudioError.invalidState }
        stopTime = try scheduledTime(when)
        context.graphDidChange()
    }

    // Schedules the start once its subclass has checked its own arguments.
    func scheduleStart(_ when: Double) throws {
        guard startTime == nil else { throw WebAudioError.invalidState }
        startTime = try scheduledTime(when)
        context.graphDidChange()
    }

    // The time exactly, or now for a time already past. A time is a double,
    // which takes only finite values.
    func scheduledTime(_ when: Double) throws -> Double {
        guard when.isFinite, when >= 0 else { throw WebAudioError.rangeError }
        return max(when, context.currentTime)
    }
}

@MainActor
public class AudioScheduledSourceNode: AudioNode {
    private var sourceHandler: AudioScheduledSourceHandler {
        unsafeDowncast(handler, to: AudioScheduledSourceHandler.self)
    }

    // Kept with the source, which may end after the caller lets go of it.
    public var onended: (() -> Void)? {
        get { sourceHandler.onended }
        set { sourceHandler.onended = newValue }
    }

    public func start(_ when: Double = 0) throws {
        try sourceHandler.start(when)
    }

    public func stop(_ when: Double = 0) throws {
        try sourceHandler.stop(when)
    }
}
#endif
