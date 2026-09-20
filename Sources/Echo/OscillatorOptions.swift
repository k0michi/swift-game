public struct OscillatorOptions: Sendable {
    // TODO: Add periodicWave after PeriodicWave is implemented.
    public var audioNodeOptions: AudioNodeOptions
    public var type: OscillatorType
    public var frequency: Float
    public var detune: Float

    public init(
        audioNodeOptions: AudioNodeOptions = AudioNodeOptions(),
        type: OscillatorType = .sine,
        frequency: Float = 440,
        detune: Float = 0
    ) {
        self.audioNodeOptions = audioNodeOptions
        self.type = type
        self.frequency = frequency
        self.detune = detune
    }
}
