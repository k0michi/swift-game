import CStbImage

// stbi_failure_reason
public struct StbImageError: Error, Equatable, CustomStringConvertible {
    public let operation: String
    public let message: String

    public var description: String {
        "\(operation) failed: \(message)"
    }

    init(operation: String) {
        self.init(operation: operation, message: stbi_failure_reason().map { String(cString: $0) } ?? "unknown error")
    }

    init(operation: String, message: String) {
        self.operation = operation
        self.message = message
    }
}
