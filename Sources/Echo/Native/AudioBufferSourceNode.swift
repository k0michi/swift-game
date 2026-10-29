// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
@MainActor
final class AudioBufferSourceHandler: AudioScheduledSourceHandler {
    private(set) var buffer: AudioBuffer?

    // With detune, a compound parameter of unbounded range: the playback
    // rate is playbackRate · 2^(detune / 1200). Both are k-rate only.
    private(set) lazy var playbackRate = AudioParamHandler(
        owner: self,
        defaultValue: 1,
        minValue: -.greatestFiniteMagnitude,
        maxValue: .greatestFiniteMagnitude,
        automationRate: .kRate,
        isAutomationRateFixed: true
    )
    private(set) lazy var detune = AudioParamHandler(
        owner: self,
        defaultValue: 0,
        minValue: -.greatestFiniteMagnitude,
        maxValue: .greatestFiniteMagnitude,
        automationRate: .kRate,
        isAutomationRateFixed: true
    )

    var loop: Bool {
        didSet { context.graphDidChange() }
    }
    // Playhead positions, in seconds of the buffer.
    // TODO: A Swift property setter cannot surface the TypeError for values that are not finite.
    var loopStart: Double {
        didSet { context.graphDidChange() }
    }
    var loopEnd: Double {
        didSet { context.graphDidChange() }
    }

    // [[buffer set]]: whether a buffer has been set, after which only nil may
    // be.
    private var bufferSet = false
    // The buffer's contents acquired when started, or when set after that.
    private(set) var content: BufferSourceContent?
    private(set) var offset = 0.0
    private(set) var duration: Double?
    let renderState = BufferSourceRenderState()

    init(context: BaseAudioContext, options: AudioBufferSourceOptions = AudioBufferSourceOptions()) throws {
        try options.validate()
        loop = options.loop
        loopStart = options.loopStart
        loopEnd = options.loopEnd
        super.init(
            context: context,
            numberOfInputs: 0,
            numberOfOutputs: 1,
            channelCount: 2,
            channelCountMode: .max,
            channelInterpretation: .speakers
        )
        playbackRate.value = options.playbackRate
        detune.value = options.detune
        if let buffer = options.buffer {
            try setBuffer(buffer)
        }
    }

    // Sets the buffer attribute.
    func setBuffer(_ buffer: AudioBuffer?) throws {
        if buffer != nil {
            guard !bufferSet else { throw WebAudioError.invalidState }
            bufferSet = true
        }
        self.buffer = buffer
        if startTime != nil {
            content = buffer.map(BufferSourceContent.init)
        }
        context.graphDidChange()
    }

    override func start(_ when: Double) throws {
        try start(when, offset: 0)
    }

    // Plays from the playhead position `offset` for `duration` seconds of
    // the buffer, however fast, or until stopped when there is none.
    func start(_ when: Double, offset: Double, duration: Double? = nil) throws {
        guard startTime == nil else { throw WebAudioError.invalidState }
        _ = try scheduledTime(when)
        // Doubles, which take only finite values.
        guard offset.isFinite, offset >= 0, duration.map({ $0.isFinite && $0 >= 0 }) ?? true else {
            throw WebAudioError.rangeError
        }
        self.offset = offset
        self.duration = duration
        content = buffer.map(BufferSourceContent.init)
        try scheduleStart(when)
    }

    override var audioParams: [AudioParamHandler] { [playbackRate, detune] }
}

// A copy of an AudioBuffer's samples, which the rendering thread reads while
// the buffer may change.
final class BufferSourceContent: Sendable {
    let channels: [[Float]]
    let sampleRate: Double
    let length: Int

    var duration: Double { Double(length) / sampleRate }

    @MainActor
    init(_ buffer: AudioBuffer) {
        channels = (0 ..< buffer.numberOfChannels).map { channel in
            var samples = [Float](repeating: 0, count: Int(buffer.length))
            // The channel exists and the array is its length.
            try! buffer.copyFromChannel(&samples, channelNumber: channel)
            return samples
        }
        sampleRate = Double(buffer.sampleRate)
        length = Int(buffer.length)
    }
}

@MainActor
public final class AudioBufferSourceNode: AudioScheduledSourceNode {
    public var buffer: AudioBuffer? { sourceHandler.buffer }

    // With detune, a compound parameter of unbounded range: the playback
    // rate is playbackRate · 2^(detune / 1200). Both are k-rate only.
    public let playbackRate: AudioParam
    public let detune: AudioParam

    public var loop: Bool {
        get { sourceHandler.loop }
        set { sourceHandler.loop = newValue }
    }
    // Playhead positions, in seconds of the buffer.
    public var loopStart: Double {
        get { sourceHandler.loopStart }
        set { sourceHandler.loopStart = newValue }
    }
    public var loopEnd: Double {
        get { sourceHandler.loopEnd }
        set { sourceHandler.loopEnd = newValue }
    }

    private var sourceHandler: AudioBufferSourceHandler {
        unsafeDowncast(handler, to: AudioBufferSourceHandler.self)
    }

    public init(context: BaseAudioContext, options: AudioBufferSourceOptions = AudioBufferSourceOptions()) throws {
        let handler = try AudioBufferSourceHandler(context: context, options: options)
        playbackRate = AudioParam(handler.playbackRate)
        detune = AudioParam(handler.detune)
        super.init(handler: handler)
    }

    // Sets the buffer attribute.
    public func setBuffer(_ buffer: AudioBuffer?) throws {
        try sourceHandler.setBuffer(buffer)
    }

    // Plays from the playhead position `offset` for `duration` seconds of
    // the buffer, however fast, or until stopped when there is none.
    public func start(_ when: Double, offset: Double, duration: Double? = nil) throws {
        try sourceHandler.start(when, offset: offset, duration: duration)
    }
}
#endif
