import CSDL3

// SDL_GetError
public struct SDLError: Error, Equatable, CustomStringConvertible {
    public let operation: String
    public let message: String

    public var description: String {
        "\(operation) failed: \(message)"
    }

    init(operation: String) {
        self.init(operation: operation, message: String(cString: SDL_GetError()))
    }

    init(operation: String, message: String) {
        self.operation = operation
        self.message = message
    }
}
