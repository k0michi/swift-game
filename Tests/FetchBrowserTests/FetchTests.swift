#if os(Emscripten)
import Fetch

@MainActor
let tests: [(String, @MainActor () async throws -> Void)] = [
    ("testGet", {
        let response = try await fetch("FetchBrowserTests.html")
        expect(response.status == 200, "status \(response.status)")
        expect(response.ok, "ok")
        expect(!response.redirected, "redirected")
        expect(response.url.hasSuffix("/FetchBrowserTests.html"), "url \(response.url)")
        expect(response.headers.get("Content-Type") == "text/html", "content-type \(response.headers.get("content-type") ?? "none")")
        expect(try await response.text().contains("FetchBrowserTests.js"), "text")
        expect(response.bodyUsed, "bodyUsed")
        await expect(.typeError("Body has already been consumed."), "reading twice") { _ = try await response.bytes() }
    }),
    ("testErrorStatus", {
        let response = try await fetch("missing")
        expect(response.status == 404, "status \(response.status)")
        expect(!response.ok, "ok")
        expect(try await response.bytes().isEmpty, "bytes")
    }),
    ("testBadRequests", {
        await expect(.typeError("Request with GET/HEAD method cannot have body."), "GET with a body") {
            _ = try await fetch("missing", RequestInit(body: "x"))
        }
        await expect(nil, "network error") {
            _ = try await fetch("http://127.0.0.1:1/")
        }
    }),
]

#endif
