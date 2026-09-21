@MainActor
public final class DelayNode: AudioNode {
    public private(set) lazy var delayTime = AudioParam(
        owner: self,
        defaultValue: 0,
        minValue: 0,
        maxValue: Float(maxDelayTime),
        automationRate: .aRate
    )

    public let maxDelayTime: Double
    let renderState: DelayRenderState

    public init(context: BaseAudioContext, options: DelayOptions = DelayOptions()) throws {
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

    public override func setChannelCount(_ channelCount: UInt32) throws {
        try super.setChannelCount(channelCount)
    }

    override var audioParams: [AudioParam] { [delayTime] }
}
