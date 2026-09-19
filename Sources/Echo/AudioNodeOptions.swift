public struct AudioNodeOptions: Sendable {
    public var channelCount: UInt32
    public var channelCountMode: ChannelCountMode
    public var channelInterpretation: ChannelInterpretation

    public init(
        channelCount: UInt32 = 2,
        channelCountMode: ChannelCountMode = .max,
        channelInterpretation: ChannelInterpretation = .speakers
    ) {
        self.channelCount = channelCount
        self.channelCountMode = channelCountMode
        self.channelInterpretation = channelInterpretation
    }
}
