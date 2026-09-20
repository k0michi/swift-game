public final class OscillatorNode: AudioScheduledSourceNode {
    // TODO: Add setPeriodicWave(_:) after PeriodicWave is implemented.
    public var type: OscillatorType {
        didSet {
            precondition(type != .custom, "Use setPeriodicWave(_:) to select a custom waveform")
            graph.setOscillatorType(id: id, type: type)
        }
    }
    public let frequency: AudioParam
    public let detune: AudioParam

    public init(context: BaseAudioContext, options: OscillatorOptions = OscillatorOptions()) {
        precondition(options.type != .custom, "A custom oscillator requires a PeriodicWave")
        let nyquist = context.sampleRate / 2
        frequency = AudioParam(
            graph: context.graph,
            defaultValue: options.frequency,
            minValue: -nyquist,
            maxValue: nyquist
        )
        detune = AudioParam(
            graph: context.graph,
            defaultValue: options.detune,
            minValue: -153_600,
            maxValue: 153_600
        )
        type = options.type
        super.init(
            context: context,
            numberOfInputs: 0,
            numberOfOutputs: 1,
            options: options.audioNodeOptions,
            processor: RenderOscillatorProcessor(
                frequency: frequency.id,
                detune: detune.id,
                type: options.type
            )
        )
    }
}
