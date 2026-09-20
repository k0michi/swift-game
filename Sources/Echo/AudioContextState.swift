public enum AudioContextState: String, CaseIterable, Sendable {
    case suspended
    case running
    case closed
    case interrupted
}
