// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
public final class ConstantSourceNode: AudioScheduledSourceNode {
    public private(set) lazy var offset = AudioParam(
        owner: self,
        defaultValue: 1,
        minValue: -.greatestFiniteMagnitude,
        maxValue: .greatestFiniteMagnitude,
        automationRate: .aRate
    )
    // The first frame at or after each time.
    var scheduledStartFrame: UInt64? { startTime.map(frame) }
    var scheduledStopFrame: UInt64? { stopTime.map(frame) }

    public init(context: BaseAudioContext) {
        super.init(
            context: context,
            numberOfInputs: 0,
            numberOfOutputs: 1,
            channelCount: 1,
            channelCountMode: .max,
            channelInterpretation: .speakers
        )
    }

    override var audioParams: [AudioParam] { [offset] }

    private func frame(_ time: Double) -> UInt64 {
        UInt64(min((time * Double(context.sampleRate)).rounded(.up), Double(UInt64.max)))
    }
}
#endif
