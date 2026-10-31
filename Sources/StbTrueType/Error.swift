// stb_truetype returns 0 or NULL when it fails, without saying why.
public struct StbTrueTypeError: Error, Equatable, CustomStringConvertible {
    public let operation: String
    public let message: String

    public var description: String {
        "\(operation) failed: \(message)"
    }

    init(operation: String, message: String) {
        self.operation = operation
        self.message = message
    }
}
