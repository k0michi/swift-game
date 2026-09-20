public struct OfflineAudioContextOptions: Sendable {
    public var numberOfChannels: UInt32
    public var length: UInt32?
    public var sampleRate: Float
    public var renderSizeHint: AudioContextRenderSize

    public init(
        numberOfChannels: UInt32 = 1,
        length: UInt32? = nil,
        sampleRate: Float,
        renderSizeHint: AudioContextRenderSize = .default
    ) {
        self.numberOfChannels = numberOfChannels
        self.length = length
        self.sampleRate = sampleRate
        self.renderSizeHint = renderSizeHint
    }
}
