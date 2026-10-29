// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
@MainActor
final class DelayHandler: AudioHandler {
    private(set) lazy var delayTime = AudioParamHandler(
        owner: self,
        defaultValue: 0,
        minValue: 0,
        maxValue: Float(maxDelayTime),
        automationRate: .aRate
    )

    let maxDelayTime: Double
    let renderState: DelayRenderState
    // A delay's tail-time: what it holds plays out after its input stops,
    // for up to its longest delay.
    private let sounding: SoundingSignal
    override var soundingSignal: SoundingSignal? { sounding }

    init(context: BaseAudioContext, options: DelayOptions = DelayOptions()) throws {
        guard options.maxDelayTime.isFinite,
              options.maxDelayTime > 0,
              options.maxDelayTime < 180,
              options.delayTime.isFinite,
              options.delayTime >= 0,
              options.delayTime <= options.maxDelayTime,
              (1 ... AudioBuffer.maximumNumberOfChannels).contains(options.channelCount ?? 2)
        else {
            throw WebAudioError.notSupported
        }
        maxDelayTime = options.maxDelayTime
        sounding = SoundingSignal(tailFrames: Int((options.maxDelayTime * Double(context.sampleRate)).rounded(.up)))
        renderState = DelayRenderState(
            maxDelayTime: options.maxDelayTime,
            sampleRate: context.sampleRate,
            channelCapacity: Int(AudioBuffer.maximumNumberOfChannels),
            quantumSize: Int(context.renderQuantumSize)
        )
        super.init(
            context: context,
            numberOfInputs: 1,
            numberOfOutputs: 1,
            channelCount: options.channelCount ?? 2,
            channelCountMode: options.channelCountMode ?? .max,
            channelInterpretation: options.channelInterpretation ?? .speakers
        )
        delayTime.value = Float(options.delayTime)
    }

    override func setChannelCount(_ channelCount: UInt32) throws {
        try super.setChannelCount(channelCount)
    }

    override var audioParams: [AudioParamHandler] { [delayTime] }
}

@MainActor
public final class DelayNode: AudioNode {
    public let delayTime: AudioParam
    public var maxDelayTime: Double { delayHandler.maxDelayTime }

    private var delayHandler: DelayHandler { unsafeDowncast(handler, to: DelayHandler.self) }

    public init(context: BaseAudioContext, options: DelayOptions = DelayOptions()) throws {
        let handler = try DelayHandler(context: context, options: options)
        delayTime = AudioParam(handler.delayTime)
        super.init(handler: handler)
    }
}
#endif
