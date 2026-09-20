public struct AudioNodeOptions: Sendable, Equatable {
    public var channelCount: UInt32?
    public var channelCountMode: ChannelCountMode?
    public var channelInterpretation: ChannelInterpretation?

    public init(
        channelCount: UInt32? = nil,
        channelCountMode: ChannelCountMode? = nil,
        channelInterpretation: ChannelInterpretation? = nil
    ) {
        self.channelCount = channelCount
        self.channelCountMode = channelCountMode
        self.channelInterpretation = channelInterpretation
    }
}
