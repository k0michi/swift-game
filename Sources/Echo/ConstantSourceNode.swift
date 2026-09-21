public final class ConstantSourceNode: AudioNode {
    public private(set) lazy var offset = AudioParam(
        owner: self,
        defaultValue: 1,
        minValue: -.greatestFiniteMagnitude,
        maxValue: .greatestFiniteMagnitude,
        automationRate: .aRate
    )
    private var startFrame: UInt64?
    private var stopFrame: UInt64?

    var scheduledStartFrame: UInt64? { startFrame }
    var scheduledStopFrame: UInt64? { stopFrame }

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

    public func start(_ when: Double = 0) throws {
        guard startFrame == nil else { throw WebAudioError.invalidState }
        startFrame = try scheduledFrame(for: when)
        context.graphDidChange()
    }

    public func stop(_ when: Double = 0) throws {
        guard startFrame != nil else { throw WebAudioError.invalidState }
        stopFrame = try scheduledFrame(for: when)
        context.graphDidChange()
    }

    override var audioParams: [AudioParam] { [offset] }

    // TODO: Enqueue parameter and scheduling changes for the rendering thread.

    private func scheduledFrame(for time: Double) throws -> UInt64 {
        let frame = (time * Double(context.sampleRate)).rounded(.up)
        guard frame.isFinite, frame >= 0, frame < Double(UInt64.max) else {
            throw WebAudioError.notSupported
        }
        return UInt64(frame)
    }
}
