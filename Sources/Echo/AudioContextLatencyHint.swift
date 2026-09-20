public enum AudioContextLatencyHint: Sendable, Equatable {
    case category(AudioContextLatencyCategory)
    case seconds(Double)
}
