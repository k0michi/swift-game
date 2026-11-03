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

// SDL_StartTextInput
@MainActor
public func startTextInput(window: Window) throws {
    guard SDL_StartTextInput(window.cPointer) else {
        throw SDLError(operation: "SDL_StartTextInput")
    }
}

// SDL_TextInputActive
@MainActor
public func textInputActive(window: Window) -> Bool {
    SDL_TextInputActive(window.cPointer)
}

// SDL_StopTextInput
@MainActor
public func stopTextInput(window: Window) throws {
    guard SDL_StopTextInput(window.cPointer) else {
        throw SDLError(operation: "SDL_StopTextInput")
    }
}

// SDL_ClearComposition
@MainActor
public func clearComposition(window: Window) throws {
    guard SDL_ClearComposition(window.cPointer) else {
        throw SDLError(operation: "SDL_ClearComposition")
    }
}

// SDL_SetTextInputArea
@MainActor
public func setTextInputArea(window: Window, rect: Rect?, cursor: Int32) throws {
    let succeeded =
        if var rect = rect?.cValue {
            SDL_SetTextInputArea(window.cPointer, &rect, cursor)
        } else {
            SDL_SetTextInputArea(window.cPointer, nil, cursor)
        }
    guard succeeded else {
        throw SDLError(operation: "SDL_SetTextInputArea")
    }
}

// SDL_GetTextInputArea
@MainActor
public func getTextInputArea(window: Window) throws -> (rect: Rect, cursor: Int32) {
    var rect = SDL_Rect()
    var cursor: Int32 = 0
    guard SDL_GetTextInputArea(window.cPointer, &rect, &cursor) else {
        throw SDLError(operation: "SDL_GetTextInputArea")
    }
    return (Rect(rect), cursor)
}

// SDL_HasScreenKeyboardSupport
@MainActor
public func hasScreenKeyboardSupport() -> Bool {
    SDL_HasScreenKeyboardSupport()
}

// SDL_ScreenKeyboardShown
@MainActor
public func screenKeyboardShown(window: Window) -> Bool {
    SDL_ScreenKeyboardShown(window.cPointer)
}
