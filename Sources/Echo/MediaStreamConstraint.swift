public enum MediaStreamConstraint: Sendable {
    case boolean(Bool)
    case constraints(MediaTrackConstraints)

    public var requested: Bool {
        switch self {
        case let .boolean(value): value
        case .constraints: true
        }
    }
}
