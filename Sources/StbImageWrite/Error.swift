// stb_image_write returns 0 when it fails, without saying why.
public struct StbImageWriteError: Error, Equatable, CustomStringConvertible {
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
