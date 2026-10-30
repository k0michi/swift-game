/// What `fetch` gets, as the Fetch API's Response. It comes when the headers
/// have, and its body is read once, with `bytes()` or `text()`.
@MainActor
public final class Response {
    public let status: Int
    public let statusText: String
    public let headers: Headers
    /// Where it came from, after any redirects.
    public let url: String
    public let redirected: Bool
    public private(set) var bodyUsed = false
    private let body: ResponseBody

    public var ok: Bool {
        (200...299).contains(status)
    }

    init(status: Int, statusText: String, headers: Headers, url: String, redirected: Bool, body: ResponseBody) {
        self.status = status
        self.statusText = statusText
        self.headers = headers
        self.url = url
        self.redirected = redirected
        self.body = body
    }

    public func bytes() async throws(FetchError) -> [UInt8] {
        guard !bodyUsed else {
            throw .typeError("Body has already been consumed.")
        }
        bodyUsed = true
        return try await body.bytes()
    }

    /// The body decoded from UTF-8, without a byte order mark.
    public func text() async throws(FetchError) -> String {
        let bytes = try await bytes()
        return String(decoding: bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? bytes.dropFirst(3) : bytes[...], as: UTF8.self)
    }
}
