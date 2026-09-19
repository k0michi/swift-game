public struct AudioContextOptions: Sendable {
    public var latencyHint: AudioContextLatency
    public var sampleRate: Float?
    public var renderSizeHint: AudioContextRenderSize

    public init(
        latencyHint: AudioContextLatency = .interactive,
        sampleRate: Float? = nil,
        renderSizeHint: AudioContextRenderSize = .default
    ) {
        self.latencyHint = latencyHint
        self.sampleRate = sampleRate
        self.renderSizeHint = renderSizeHint
    }
}
