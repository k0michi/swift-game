// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
@MainActor
final class ConstantSourceHandler: AudioScheduledSourceHandler {
    private(set) lazy var offset = AudioParamHandler(
        owner: self,
        defaultValue: 1,
        minValue: -.greatestFiniteMagnitude,
        maxValue: .greatestFiniteMagnitude,
        automationRate: .aRate
    )
    // The first frame at or after each time.
    var scheduledStartFrame: UInt64? { startTime.map(frame) }
    var scheduledStopFrame: UInt64? { stopTime.map(frame) }

    init(context: BaseAudioContext) {
        super.init(
            context: context,
            numberOfInputs: 0,
            numberOfOutputs: 1,
            channelCount: 1,
            channelCountMode: .max,
            channelInterpretation: .speakers
        )
    }

    override var audioParams: [AudioParamHandler] { [offset] }

    private func frame(_ time: Double) -> UInt64 {
        UInt64(min((time * Double(context.sampleRate)).rounded(.up), Double(UInt64.max)))
    }
}

@MainActor
public final class ConstantSourceNode: AudioScheduledSourceNode {
    public let offset: AudioParam

    public init(context: BaseAudioContext) {
        let handler = ConstantSourceHandler(context: context)
        offset = AudioParam(handler.offset)
        super.init(handler: handler)
    }
}
#endif
