public final class GainNode: AudioNode {
    public let gain: AudioParam

    public init(context: BaseAudioContext, options: GainOptions = GainOptions()) {
        gain = AudioParam(
            graph: context.graph,
            defaultValue: options.gain,
            minValue: -Float.greatestFiniteMagnitude,
            maxValue: Float.greatestFiniteMagnitude
        )
        super.init(
            context: context,
            numberOfInputs: 1,
            numberOfOutputs: 1,
            options: options.audioNodeOptions,
            kind: .gain(gain.id)
        )
    }
}
