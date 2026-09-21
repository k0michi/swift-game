public struct DelayOptions: Sendable, Equatable {
    public var channelCount: UInt32?
    public var channelCountMode: ChannelCountMode?
    public var channelInterpretation: ChannelInterpretation?
    public var maxDelayTime: Double
    public var delayTime: Double

    public init(
        channelCount: UInt32? = nil,
        channelCountMode: ChannelCountMode? = nil,
        channelInterpretation: ChannelInterpretation? = nil,
        maxDelayTime: Double = 1,
        delayTime: Double = 0
    ) {
        self.channelCount = channelCount
        self.channelCountMode = channelCountMode
        self.channelInterpretation = channelInterpretation
        self.maxDelayTime = maxDelayTime
        self.delayTime = delayTime
    }
}
