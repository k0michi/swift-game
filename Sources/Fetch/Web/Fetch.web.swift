#if os(Emscripten)
import CFetchWeb

/// Requests `input` with the browser's fetch, which resolves a relative URL
/// against the page's. It follows redirects, and fails with a TypeError on
/// network errors but not on error statuses.
@MainActor
public func fetch(_ input: String, _ options: RequestInit = RequestInit()) async throws(FetchError) -> Response {
    let prepared = try PreparedRequest(options)
    let headers = prepared.headers.fields.map { "\($0.name): \($0.value)\r\n" }.joined()
    let result: Result<Int32, FetchError> = await withUnsafeContinuation { continuation in
        let settlement = Unmanaged.passRetained(Settlement(continuation)).toOpaque()
        let body = prepared.body ?? []
        body.withUnsafeBufferPointer { body in
            fetch_web_fetch(
                input, prepared.method, headers, body.baseAddress, Int32(body.count), prepared.body == nil ? 0 : 1,
                { settlement, response, error in
                    Unmanaged<Settlement<Int32>>.fromOpaque(settlement!).takeRetainedValue().continuation.resume(
                        returning: response != 0 ? .success(response) : .failure(typeError(error)))
                }, settlement)
        }
    }
    let handle = try result.get()
    var responseHeaders = Headers()
    for line in string(handle, "headers").split(separator: "\r\n") {
        let colon = line.firstRange(of: ": ")!
        responseHeaders.append(String(line[..<colon.lowerBound]), String(line[colon.upperBound...]))
    }
    return Response(
        status: Int(fetch_web_get_number(handle, "status")),
        statusText: string(handle, "statusText"),
        headers: responseHeaders,
        url: string(handle, "url"),
        redirected: fetch_web_get_number(handle, "redirected") != 0,
        body: ResponseBody(handle: handle)
    )
}

/// The browser's response, which reads the body.
final class ResponseBody {
    let handle: Int32

    init(handle: Int32) {
        self.handle = handle
    }

    deinit {
        fetch_web_release(handle)
    }

    @MainActor
    func bytes() async throws(FetchError) -> [UInt8] {
        let result: Result<[UInt8], FetchError> = await withUnsafeContinuation { continuation in
            let settlement = Unmanaged.passRetained(Settlement(continuation)).toOpaque()
            fetch_web_response_bytes(handle, { settlement, bytes, length, error in
                let continuation = Unmanaged<Settlement<[UInt8]>>.fromOpaque(settlement!).takeRetainedValue().continuation
                guard bytes != 0 else {
                    continuation.resume(returning: .failure(typeError(error)))
                    return
                }
                defer { fetch_web_release(bytes) }
                continuation.resume(returning: .success([UInt8](unsafeUninitializedCapacity: Int(length)) { buffer, count in
                    fetch_web_copy_bytes(bytes, buffer.baseAddress)
                    count = Int(length)
                }))
            }, settlement)
        }
        return try result.get()
    }
}

private final class Settlement<Value> {
    let continuation: UnsafeContinuation<Result<Value, FetchError>, Never>

    init(_ continuation: UnsafeContinuation<Result<Value, FetchError>, Never>) {
        self.continuation = continuation
    }
}

private func string(_ handle: Int32, _ property: String) -> String {
    let length = Int(fetch_web_get_string(handle, property, nil, 0))
    return String(unsafeUninitializedCapacity: length + 1) { buffer in
        buffer.withMemoryRebound(to: CChar.self) {
            _ = fetch_web_get_string(handle, property, $0.baseAddress, Int32($0.count))
        }
        return length
    }
}

/// The TypeError with the message of the browser's error, which it releases.
private func typeError(_ error: Int32) -> FetchError {
    defer { fetch_web_release(error) }
    return .typeError(string(error, "message"))
}
#endif
