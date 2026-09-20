public enum ChannelCountMode: String, CaseIterable, Sendable {
    case max
    case clampedMax = "clamped-max"
    case explicit
}
