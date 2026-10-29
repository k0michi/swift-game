// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
@MainActor
final class GainHandler: AudioHandler {
    private(set) lazy var gain = AudioParamHandler(
        owner: self,
        defaultValue: 1,
        minValue: -.greatestFiniteMagnitude,
        maxValue: .greatestFiniteMagnitude,
        automationRate: .aRate
    )

    init(context: BaseAudioContext, options: GainOptions = GainOptions()) throws {
        guard (1 ... AudioBuffer.maximumNumberOfChannels).contains(options.channelCount ?? 2) else {
            throw WebAudioError.notSupported
        }
        // The option is a float, which takes only finite values.
        guard options.gain.isFinite else { throw WebAudioError.rangeError }
        super.init(
            context: context,
            numberOfInputs: 1,
            numberOfOutputs: 1,
            channelCount: options.channelCount ?? 2,
            channelCountMode: options.channelCountMode ?? .max,
            channelInterpretation: options.channelInterpretation ?? .speakers
        )
        gain.value = options.gain
    }

    override var audioParams: [AudioParamHandler] { [gain] }
}

@MainActor
public final class GainNode: AudioNode {
    public let gain: AudioParam

    public init(context: BaseAudioContext, options: GainOptions = GainOptions()) throws {
        let handler = try GainHandler(context: context, options: options)
        gain = AudioParam(handler.gain)
        super.init(handler: handler)
    }
}
#endif
