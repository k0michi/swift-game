import CFreeType

// FT_Error
public struct FreeTypeError: Error, Equatable, CustomStringConvertible {
    public let operation: String
    /// The FT_Error, which `message` names.
    public let code: Int32
    public let message: String

    public var description: String {
        "\(operation) failed: \(message)"
    }

    init(operation: String, code: FT_Error) {
        self.operation = operation
        self.code = code
        message = String(cString: CFreeType_ErrorString(code))
    }
}

func check(_ operation: String, _ error: FT_Error) throws {
    guard error == 0 else { throw FreeTypeError(operation: operation, code: error) }
}
