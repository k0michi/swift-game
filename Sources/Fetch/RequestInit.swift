/// What `fetch` sends, as the Fetch API's RequestInit.
public struct RequestInit: Sendable {
    public var method: String
    public var headers: Headers
    public var body: BodyInit?

    public init(method: String = "GET", headers: Headers = Headers(), body: BodyInit? = nil) {
        self.method = method
        self.headers = headers
        self.body = body
    }
}

/// A request's body: bytes, or text sent as UTF-8.
public enum BodyInit: Sendable, ExpressibleByStringLiteral {
    case bytes([UInt8])
    case text(String)

    public init(stringLiteral value: String) {
        self = .text(value)
    }
}

/// A request checked and normalized as the Fetch API does before sending.
struct PreparedRequest {
    var method: String
    var headers: Headers
    var body: [UInt8]?

    init(_ options: RequestInit) throws(FetchError) {
        method = options.method
        let upper = method.uppercased()
        guard !method.isEmpty, method.utf8.allSatisfy({ $0 > 0x20 && $0 < 0x7F && !"()<>@,;:\\\"/[]?={}".utf8.contains($0) }) else {
            throw .typeError("'\(method)' is not a valid HTTP method.")
        }
        guard !["CONNECT", "TRACE", "TRACK"].contains(upper) else {
            throw .typeError("'\(method)' HTTP method is unsupported.")
        }
        if ["DELETE", "GET", "HEAD", "OPTIONS", "POST", "PUT"].contains(upper) {
            method = upper
        }
        headers = options.headers
        guard headers.isValid else {
            throw .typeError("Invalid header name or value.")
        }
        switch options.body {
        case nil:
            body = nil
        case let .bytes(bytes):
            body = bytes
        case let .text(text):
            body = Array(text.utf8)
            if !headers.has("content-type") {
                headers.append("content-type", "text/plain;charset=UTF-8")
            }
        }
        if body != nil && (method == "GET" || method == "HEAD") {
            throw .typeError("Request with GET/HEAD method cannot have body.")
        }
    }
}
