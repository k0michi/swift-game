public struct OfflineAudioContextOptions: Sendable, Equatable {
    public var numberOfChannels: UInt32
    public var length: UInt32?
    public var sampleRate: Float
    public var renderSizeHint: AudioContextRenderSizeHint

    public init(
        numberOfChannels: UInt32 = 1,
        length: UInt32? = nil,
        sampleRate: Float,
        renderSizeHint: AudioContextRenderSizeHint = .category(.default)
    ) {
        self.numberOfChannels = numberOfChannels
        self.length = length
        self.sampleRate = sampleRate
        self.renderSizeHint = renderSizeHint
    }
}
