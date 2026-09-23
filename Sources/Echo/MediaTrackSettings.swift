public struct MediaTrackSettings: Sendable {
    public let sampleRate: UInt32?
    public let channelCount: UInt32?

    public init(sampleRate: UInt32? = nil, channelCount: UInt32? = nil) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }
}
