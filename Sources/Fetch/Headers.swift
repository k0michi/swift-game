/// The headers of a request or a response, as the Fetch API's Headers: names
/// match whatever their case, and `get(_:)` joins the values of a name.
public struct Headers: Sendable, Sequence, ExpressibleByDictionaryLiteral {
    /// Lowercased names with their values, in the order they were added.
    private(set) var fields: [(name: String, value: String)] = []

    public init() {}

    public init(_ fields: [(String, String)]) {
        for (name, value) in fields {
            append(name, value)
        }
    }

    public init(dictionaryLiteral elements: (String, String)...) {
        self.init(elements)
    }

    public mutating func append(_ name: String, _ value: String) {
        fields.append((name.lowercased(), normalize(value)))
    }

    /// Replaces the values of `name` with `value`, where the first was.
    public mutating func set(_ name: String, _ value: String) {
        let name = name.lowercased()
        var replaced = false
        fields = fields.compactMap { field in
            guard field.name == name else { return field }
            defer { replaced = true }
            return replaced ? nil : (name, normalize(value))
        }
        if !replaced {
            fields.append((name, normalize(value)))
        }
    }

    public mutating func delete(_ name: String) {
        let name = name.lowercased()
        fields.removeAll { $0.name == name }
    }

    /// The values of `name` joined with ", ", or nil if it has none.
    public func get(_ name: String) -> String? {
        let name = name.lowercased()
        let values = fields.filter { $0.name == name }.map(\.value)
        return values.isEmpty ? nil : values.joined(separator: ", ")
    }

    public func has(_ name: String) -> Bool {
        let name = name.lowercased()
        return fields.contains { $0.name == name }
    }

    /// Each name in order with its values joined, but each value of
    /// set-cookie on its own, as the Fetch API iterates them.
    public func makeIterator() -> IndexingIterator<[(name: String, value: String)]> {
        var names: [String] = []
        for field in fields where !names.contains(field.name) {
            names.append(field.name)
        }
        return names.sorted().flatMap { name in
            name == "set-cookie"
                ? fields.filter { $0.name == name }
                : [(name, get(name)!)]
        }.makeIterator()
    }

    /// Whether the names are tokens and the values have no line breaks or
    /// nulls, which HTTP needs.
    var isValid: Bool {
        fields.allSatisfy { field in
            !field.name.isEmpty
                && field.name.utf8.allSatisfy(isTokenCharacter)
                && !field.value.utf8.contains { $0 == 0 || $0 == 0x0A || $0 == 0x0D }
        }
    }
}

/// Without the spaces and tabs around it, as the Fetch API keeps values.
private func normalize(_ value: String) -> String {
    let isWhitespace = { (scalar: Unicode.Scalar) in [" ", "\t", "\n", "\r"].contains(scalar) }
    let scalars = value.unicodeScalars
    guard let start = scalars.firstIndex(where: { !isWhitespace($0) }) else { return "" }
    let end = scalars.lastIndex(where: { !isWhitespace($0) })!
    return String(scalars[start...end])
}

private func isTokenCharacter(_ byte: UInt8) -> Bool {
    switch byte {
    case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
         UInt8(ascii: "0")...UInt8(ascii: "9"):
        true
    default:
        "!#$%&'*+-.^_`|~".utf8.contains(byte)
    }
}
