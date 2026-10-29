@MainActor
public struct OscillatorOptions {
    public var channelCount: UInt32?
    public var channelCountMode: ChannelCountMode?
    public var channelInterpretation: ChannelInterpretation?
    public var type: OscillatorType
    public var frequency: Float
    public var detune: Float
    // When given, it is used whatever `type` is, as if it were "custom".
    public var periodicWave: PeriodicWave?

    public init(
        channelCount: UInt32? = nil,
        channelCountMode: ChannelCountMode? = nil,
        channelInterpretation: ChannelInterpretation? = nil,
        type: OscillatorType = .sine,
        frequency: Float = 440,
        detune: Float = 0,
        periodicWave: PeriodicWave? = nil
    ) {
        self.channelCount = channelCount
        self.channelCountMode = channelCountMode
        self.channelInterpretation = channelInterpretation
        self.type = type
        self.frequency = frequency
        self.detune = detune
        self.periodicWave = periodicWave
    }

    // Throws what the options' own values make the constructor throw.
    func validate() throws {
        // The members are floats, which take only finite values.
        guard frequency.isFinite, detune.isFinite else { throw WebAudioError.rangeError }
        guard type != .custom || periodicWave != nil else { throw WebAudioError.invalidState }
    }
}
