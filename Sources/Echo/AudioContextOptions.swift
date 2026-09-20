public struct AudioContextOptions: Sendable, Equatable {
    public var latencyHint: AudioContextLatencyHint
    public var sampleRate: Float?
    public var sinkId: AudioSinkIdentifier?
    public var renderSizeHint: AudioContextRenderSizeHint

    public init(
        latencyHint: AudioContextLatencyHint = .category(.interactive),
        sampleRate: Float? = nil,
        sinkId: AudioSinkIdentifier? = nil,
        renderSizeHint: AudioContextRenderSizeHint = .category(.default)
    ) {
        self.latencyHint = latencyHint
        self.sampleRate = sampleRate
        self.sinkId = sinkId
        self.renderSizeHint = renderSizeHint
    }
}
