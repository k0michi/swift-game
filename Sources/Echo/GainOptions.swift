public struct GainOptions: Sendable, Equatable {
    public var channelCount: UInt32?
    public var channelCountMode: ChannelCountMode?
    public var channelInterpretation: ChannelInterpretation?
    public var gain: Float

    public init(
        channelCount: UInt32? = nil,
        channelCountMode: ChannelCountMode? = nil,
        channelInterpretation: ChannelInterpretation? = nil,
        gain: Float = 1
    ) {
        self.channelCount = channelCount
        self.channelCountMode = channelCountMode
        self.channelInterpretation = channelInterpretation
        self.gain = gain
    }
}
