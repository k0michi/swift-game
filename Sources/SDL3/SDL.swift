import CSDL3

public enum SDLInitializationError: Error, Equatable, CustomStringConvertible {
    case initializationFailed(String)

    public var description: String {
        switch self {
        case .initializationFailed(let message):
            "SDL initialization failed: \(message)"
        }
    }
}

@MainActor
public enum SDL {
    public static func initialize() throws {
        guard SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) else {
            throw SDLInitializationError.initializationFailed(String(cString: SDL_GetError()))
        }
    }

    public static func shutdown() {
        SDL_Quit()
    }
}
