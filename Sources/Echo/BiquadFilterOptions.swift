public struct BiquadFilterOptions: Sendable, Equatable {
    public var channelCount: UInt32?
    public var channelCountMode: ChannelCountMode?
    public var channelInterpretation: ChannelInterpretation?
    public var type: BiquadFilterType
    public var Q: Float
    public var detune: Float
    public var frequency: Float
    public var gain: Float

    public init(
        channelCount: UInt32? = nil,
        channelCountMode: ChannelCountMode? = nil,
        channelInterpretation: ChannelInterpretation? = nil,
        type: BiquadFilterType = .lowpass,
        Q: Float = 1,
        detune: Float = 0,
        frequency: Float = 350,
        gain: Float = 0
    ) {
        self.channelCount = channelCount
        self.channelCountMode = channelCountMode
        self.channelInterpretation = channelInterpretation
        self.type = type
        self.Q = Q
        self.detune = detune
        self.frequency = frequency
        self.gain = gain
    }

    // Throws what the options' own values make the constructor throw.
    func validate() throws {
        // The members are floats, which take only finite values.
        guard [Q, detune, frequency, gain].allSatisfy(\.isFinite) else { throw WebAudioError.rangeError }
    }
}
