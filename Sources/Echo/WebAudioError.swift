public enum WebAudioError: Error, Sendable, Equatable {
    case invalidAccess
    case invalidState
    case indexSize
    case notSupported
    case rangeError
}
