public struct MediaTrackConstraints: Sendable {
    public var sampleRate: UInt32?
    public var channelCount: UInt32?
    public var deviceId: String?

    public init(sampleRate: UInt32? = nil, channelCount: UInt32? = nil, deviceId: String? = nil) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.deviceId = deviceId
    }
}
