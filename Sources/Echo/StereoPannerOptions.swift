public struct StereoPannerOptions: Sendable, Equatable {
    public var channelCount: UInt32?
    public var channelCountMode: ChannelCountMode?
    public var channelInterpretation: ChannelInterpretation?
    public var pan: Float

    public init(
        channelCount: UInt32? = nil,
        channelCountMode: ChannelCountMode? = nil,
        channelInterpretation: ChannelInterpretation? = nil,
        pan: Float = 0
    ) {
        self.channelCount = channelCount
        self.channelCountMode = channelCountMode
        self.channelInterpretation = channelInterpretation
        self.pan = pan
    }
}
