import Fetch
import NIOCore
import NIOHTTP1
import NIOPosix
import Testing

@Suite("Headers")
struct HeadersTests {
    @Test
    func namesMatchWhateverTheirCase() {
        var headers: Headers = ["Content-Type": "text/plain"]
        #expect(headers.get("content-type") == "text/plain")
        #expect(headers.has("CONTENT-TYPE"))
        headers.delete("Content-type")
        #expect(!headers.has("content-type"))
    }

    @Test
    func valuesOfANameAreJoined() {
        var headers = Headers()
        headers.append("Accept", "text/html")
        headers.append("accept", " application/json\t")
        #expect(headers.get("accept") == "text/html, application/json")
        headers.set("Accept", "*/*")
        #expect(headers.get("accept") == "*/*")
    }

    @Test
    func iterationIsSortedAndCombined() {
        let headers = Headers([("b", "1"), ("a", "2"), ("b", "3"), ("Set-Cookie", "x"), ("set-cookie", "y")])
        #expect(headers.map(\.name) == ["a", "b", "set-cookie", "set-cookie"])
        #expect(headers.map(\.value) == ["2", "1, 3", "x", "y"])
    }
}

/// A server on the loopback for the tests:
/// - /echo answers with the request's method and body, and its x-test
///   header in its own.
/// - /redirect redirects to /echo.
/// - Anything else is 404.
private final class TestHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private var head: HTTPRequestHead?
    private var body: [UInt8] = []

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case let .head(head):
            self.head = head
            body = []
        case let .body(buffer):
            body += buffer.readableBytesView
        case .end:
            guard let head else { return }
            var headers = HTTPHeaders()
            let status: HTTPResponseStatus
            var content: [UInt8] = []
            switch head.uri {
            case "/echo":
                status = .ok
                content = Array("\(head.method.rawValue) ".utf8) + body
                headers.add(name: "X-Test", value: head.headers["x-test"].joined(separator: ", "))
                headers.add(name: "X-Content-Type", value: head.headers["content-type"].joined(separator: ", "))
            case "/redirect":
                status = .found
                headers.add(name: "Location", value: "/echo")
            default:
                status = .notFound
            }
            headers.add(name: "Content-Length", value: "\(content.count)")
            context.write(wrapOutboundOut(.head(HTTPResponseHead(version: head.version, status: status, headers: headers))), promise: nil)
            context.write(wrapOutboundOut(.body(.byteBuffer(ByteBuffer(bytes: content)))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        }
    }
}

@MainActor
private func withServer(_ body: (String) async throws -> Void) async throws {
    let channel = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
        .childChannelInitializer { channel in
            channel.pipeline.configureHTTPServerPipeline().flatMap {
                channel.pipeline.addHandler(TestHandler())
            }
        }
        .bind(host: "127.0.0.1", port: 0)
        .get()
    do {
        try await body("http://127.0.0.1:\(channel.localAddress!.port!)")
    } catch {
        try await channel.close()
        throw error
    }
    try await channel.close()
}

@Suite("fetch")
@MainActor
struct FetchTests {
    @Test
    func getsAResponse() async throws {
        try await withServer { origin in
            let response = try await fetch("\(origin)/echo", RequestInit(headers: ["X-Test": "yes"]))
            #expect(response.status == 200)
            #expect(response.statusText == "OK")
            #expect(response.ok)
            #expect(!response.redirected)
            #expect(response.url == "\(origin)/echo")
            #expect(response.headers.get("x-test") == "yes")
            #expect(try await response.text() == "GET ")
        }
    }

    @Test
    func postsABody() async throws {
        try await withServer { origin in
            let text = try await fetch("\(origin)/echo", RequestInit(method: "post", body: "hello"))
            #expect(text.headers.get("x-content-type") == "text/plain;charset=UTF-8")
            #expect(try await text.text() == "POST hello")
            let bytes = try await fetch("\(origin)/echo", RequestInit(method: "PUT", body: .bytes([1, 2, 3])))
            #expect(bytes.headers.get("x-content-type") == "")
            #expect(try await bytes.bytes() == Array("PUT ".utf8) + [1, 2, 3])
        }
    }

    @Test
    func followsRedirects() async throws {
        try await withServer { origin in
            let response = try await fetch("\(origin)/redirect")
            #expect(response.status == 200)
            #expect(response.redirected)
            #expect(response.url == "\(origin)/echo")
        }
    }

    @Test
    func errorStatusesAreResponses() async throws {
        try await withServer { origin in
            let response = try await fetch("\(origin)/missing")
            #expect(response.status == 404)
            #expect(!response.ok)
            #expect(try await response.bytes() == [])
        }
    }

    @Test
    func aBodyIsReadOnce() async throws {
        try await withServer { origin in
            let response = try await fetch("\(origin)/echo")
            #expect(!response.bodyUsed)
            _ = try await response.bytes()
            #expect(response.bodyUsed)
            await #expect(throws: FetchError.typeError("Body has already been consumed.")) {
                try await response.text()
            }
        }
    }

    @Test
    func badRequestsFailWithATypeError() async {
        await #expect(throws: FetchError.typeError("Request with GET/HEAD method cannot have body.")) {
            try await fetch("http://127.0.0.1:1/", RequestInit(body: "x"))
        }
        await #expect(throws: FetchError.typeError("'trace' HTTP method is unsupported.")) {
            try await fetch("http://127.0.0.1:1/", RequestInit(method: "trace"))
        }
        await #expect(throws: FetchError.typeError("Invalid header name or value.")) {
            try await fetch("http://127.0.0.1:1/", RequestInit(headers: ["X-Test": "a\r\nb"]))
        }
    }

    @Test
    func networkErrorsFailWithATypeError() async {
        await #expect(throws: FetchError.self) {
            try await fetch("http://127.0.0.1:1/")
        }
    }
}
