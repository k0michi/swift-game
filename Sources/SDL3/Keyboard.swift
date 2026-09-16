import CSDL3

// SDL_KeyboardID
public struct KeyboardID: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

// SDL_GetKeyboardState
public struct KeyboardState: Sendable {
    private let keys: [Bool]

    init(pointer: UnsafePointer<Bool>, count: Int32) {
        keys = Array(UnsafeBufferPointer(start: pointer, count: Int(count)))
    }

    public subscript(scancode: Scancode) -> Bool {
        keys.indices.contains(Int(scancode.rawValue))
            ? keys[Int(scancode.rawValue)]
            : false
    }
}

// SDL_GetKeyboardState
@MainActor
public func getKeyboardState() -> KeyboardState {
    var count: Int32 = 0
    let pointer = SDL_GetKeyboardState(&count)
    return KeyboardState(pointer: pointer!, count: count)
}
