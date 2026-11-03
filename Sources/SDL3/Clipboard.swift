import CSDL3

// SDL_SetClipboardText
@MainActor
public func setClipboardText(text: String) throws {
    guard SDL_SetClipboardText(text) else {
        throw SDLError(operation: "SDL_SetClipboardText")
    }
}

// SDL_GetClipboardText, which is empty when there is none or it fails.
@MainActor
public func getClipboardText() -> String {
    guard let text = SDL_GetClipboardText() else { return "" }
    defer { SDL_free(text) }
    return String(cString: text)
}

// SDL_HasClipboardText
@MainActor
public func hasClipboardText() -> Bool {
    SDL_HasClipboardText()
}

// SDL_SetPrimarySelectionText
@MainActor
public func setPrimarySelectionText(text: String) throws {
    guard SDL_SetPrimarySelectionText(text) else {
        throw SDLError(operation: "SDL_SetPrimarySelectionText")
    }
}

// SDL_GetPrimarySelectionText, which is empty when there is none or it fails.
@MainActor
public func getPrimarySelectionText() -> String {
    guard let text = SDL_GetPrimarySelectionText() else { return "" }
    defer { SDL_free(text) }
    return String(cString: text)
}

// SDL_HasPrimarySelectionText
@MainActor
public func hasPrimarySelectionText() -> Bool {
    SDL_HasPrimarySelectionText()
}
