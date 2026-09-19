public enum AudioContextLatency: Sendable {
    case balanced
    case interactive
    case playback
    case seconds(Double)
}
