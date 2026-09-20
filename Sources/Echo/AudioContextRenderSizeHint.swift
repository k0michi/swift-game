public enum AudioContextRenderSizeHint: Sendable, Equatable {
    case category(AudioContextRenderSizeCategory)
    case frameCount(UInt32)
}
