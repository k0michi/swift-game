// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
@MainActor
final class StereoPannerHandler: AudioHandler {
    private(set) lazy var pan = AudioParamHandler(
        owner: self,
        defaultValue: 0,
        minValue: -1,
        maxValue: 1,
        automationRate: .aRate
    )

    init(context: BaseAudioContext, options: StereoPannerOptions = StereoPannerOptions()) throws {
        let channelCount = options.channelCount ?? 2
        guard (1 ... AudioBuffer.maximumNumberOfChannels).contains(channelCount) else {
            throw WebAudioError.notSupported
        }
        // The option is a float, which takes only finite values.
        guard options.pan.isFinite else { throw WebAudioError.rangeError }
        let channelCountMode = options.channelCountMode ?? .clampedMax
        try Self.check(channelCount: channelCount)
        try Self.check(channelCountMode: channelCountMode)
        super.init(
            context: context,
            numberOfInputs: 1,
            numberOfOutputs: 1,
            channelCount: channelCount,
            channelCountMode: channelCountMode,
            channelInterpretation: options.channelInterpretation ?? .speakers
        )
        pan.value = options.pan
    }

    override func setChannelCount(_ channelCount: UInt32) throws {
        try Self.check(channelCount: channelCount)
        try super.setChannelCount(channelCount)
    }

    override func setChannelCountMode(_ channelCountMode: ChannelCountMode) throws {
        try Self.check(channelCountMode: channelCountMode)
        try super.setChannelCountMode(channelCountMode)
    }

    override var audioParams: [AudioParamHandler] { [pan] }

    // The input is at most stereo.
    private static func check(channelCount: UInt32) throws {
        guard channelCount <= 2 else { throw WebAudioError.notSupported }
    }

    private static func check(channelCountMode: ChannelCountMode) throws {
        guard channelCountMode != .max else { throw WebAudioError.notSupported }
    }
}

@MainActor
public final class StereoPannerNode: AudioNode {
    public let pan: AudioParam

    public init(context: BaseAudioContext, options: StereoPannerOptions = StereoPannerOptions()) throws {
        let handler = try StereoPannerHandler(context: context, options: options)
        pan = AudioParam(handler.pan)
        super.init(handler: handler)
    }
}
#endif
