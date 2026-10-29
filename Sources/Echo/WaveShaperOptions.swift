public struct WaveShaperOptions: Sendable, Equatable {
    public var channelCount: UInt32?
    public var channelCountMode: ChannelCountMode?
    public var channelInterpretation: ChannelInterpretation?
    public var curve: [Float]?
    public var oversample: OverSampleType

    public init(
        channelCount: UInt32? = nil,
        channelCountMode: ChannelCountMode? = nil,
        channelInterpretation: ChannelInterpretation? = nil,
        curve: [Float]? = nil,
        oversample: OverSampleType = .none
    ) {
        self.channelCount = channelCount
        self.channelCountMode = channelCountMode
        self.channelInterpretation = channelInterpretation
        self.curve = curve
        self.oversample = oversample
    }
}
