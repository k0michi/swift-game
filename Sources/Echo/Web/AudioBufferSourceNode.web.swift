#if os(Emscripten)
@MainActor
public final class AudioBufferSourceNode: AudioScheduledSourceNode {
    public private(set) var buffer: AudioBuffer?

    public private(set) lazy var playbackRate = AudioParam(context: context, object: object.object("playbackRate")!)
    public private(set) lazy var detune = AudioParam(context: context, object: object.object("detune")!)

    public var loop: Bool {
        get { object.number("loop") != 0 }
        // A boolean takes any value.
        set { try! object.set("loop", newValue ? 1 : 0) }
    }
    // TODO: A Swift property setter cannot surface the TypeError for values that are not finite.
    public var loopStart: Double {
        get { object.number("loopStart") }
        set { try? object.set("loopStart", newValue) }
    }
    public var loopEnd: Double {
        get { object.number("loopEnd") }
        set { try? object.set("loopEnd", newValue) }
    }

    // [[buffer set]], kept here as the browser's buffer is a copy that Echo
    // makes.
    private var bufferSet = false
    private var started = false
    // The browser's copy of `buffer`.
    private var browserBuffer: JSObjectReference?

    public init(context: BaseAudioContext, options: AudioBufferSourceOptions = AudioBufferSourceOptions()) throws {
        try options.validate()
        super.init(
            context: context,
            object: try JSObjectReference.new("AudioBufferSourceNode", context: context.object, options: [
                ("detune", .number(Double(options.detune))),
                ("loop", .bool(options.loop)),
                ("loopEnd", .number(options.loopEnd)),
                ("loopStart", .number(options.loopStart)),
                ("playbackRate", .number(Double(options.playbackRate))),
            ])
        )
        if let buffer = options.buffer {
            try setBuffer(buffer)
        }
    }

    // Sets the buffer attribute. Its samples go to the browser when acquired:
    // when started, or now if already started.
    public func setBuffer(_ buffer: AudioBuffer?) throws {
        if buffer != nil {
            guard !bufferSet else { throw WebAudioError.invalidState }
            bufferSet = true
        }
        self.buffer = buffer
        browserBuffer = try buffer.map { buffer in
            try JSObjectReference.new("AudioBuffer", options: [
                ("numberOfChannels", .number(Double(buffer.numberOfChannels))),
                ("length", .number(Double(buffer.length))),
                ("sampleRate", .number(Double(buffer.sampleRate))),
            ])
        }
        if started {
            try acquireContent()
        }
        try object.set("buffer", object: browserBuffer)
    }

    public override func start(_ when: Double = 0) throws {
        try start(when, offset: 0)
    }

    // Plays from the playhead position `offset` for `duration` seconds of
    // the buffer, however fast, or until stopped when there is none.
    public func start(_ when: Double, offset: Double, duration: Double? = nil) throws {
        guard !started else { throw WebAudioError.invalidState }
        try acquireContent()
        try object.call("start", nil, [when, offset] + (duration.map { [$0] } ?? []))
        started = true
        keepUntilEnded()
    }

    // Copies the buffer's samples into the browser's copy.
    private func acquireContent() throws {
        guard let buffer, let browserBuffer else { return }
        for channel in 0 ..< buffer.numberOfChannels {
            var samples = [Float](repeating: 0, count: Int(buffer.length))
            try buffer.copyFromChannel(&samples, channelNumber: channel)
            try browserBuffer.call("copyToChannel", floats: samples, [Double(channel)])
        }
    }
}
#endif
