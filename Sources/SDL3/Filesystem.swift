import CSDL3

// SDL_GetBasePath
public func getBasePath() throws -> String {
    guard let path = SDL_GetBasePath() else { throw SDLError(operation: "SDL_GetBasePath") }
    return String(cString: path)
}
