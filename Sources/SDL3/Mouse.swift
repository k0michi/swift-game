import CSDL3

// SDL_MouseID
public struct MouseID: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

// SDL_MouseWheelDirection
public struct MouseWheelDirection: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let normal = Self(rawValue: 0)
    public static let flipped = Self(rawValue: 1)
}

// SDL_MouseButtonFlags
public struct MouseButtonFlags: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let left = Self(rawValue: 1 << 0)
    public static let middle = Self(rawValue: 1 << 1)
    public static let right = Self(rawValue: 1 << 2)
    public static let x1 = Self(rawValue: 1 << 3)
    public static let x2 = Self(rawValue: 1 << 4)
}

// SDL_GetMouseState
@MainActor
public func getMouseState() -> (flags: MouseButtonFlags, x: Float, y: Float) {
    var x: Float = 0
    var y: Float = 0
    let flags = SDL_GetMouseState(&x, &y)
    return (MouseButtonFlags(rawValue: flags), x, y)
}
