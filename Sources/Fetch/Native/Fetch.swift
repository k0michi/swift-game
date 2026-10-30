#if !os(Emscripten)
import AsyncHTTPClient
import NIOCore
import NIOHTTP1

/// AsyncHTTPClient's shared client set up as a browser, but failing as soon
/// as a connection does, as a browser does, rather than trying again, or on
/// Apple platforms waiting for the network to change, until the connect
/// timeout.
private let client: HTTPClient = {
    var configuration = HTTPClient.Configuration.singletonConfiguration
    configuration.connectionPool.retryConnectionEstablishment = false
    configuration.networkFrameworkWaitForConnectivity = false
    return HTTPClient(eventLoopGroup: HTTPClient.defaultEventLoopGroup, configuration: configuration)
}()

/// Requests `input`, an absolute URL, as the Fetch API's fetch does, with
/// AsyncHTTPClient. It follows redirects, and fails with a TypeError on
/// network errors but not on error statuses.
@MainActor
public func fetch(_ input: String, _ options: RequestInit = RequestInit()) async throws(FetchError) -> Response {
    let prepared = try PreparedRequest(options)
    var request = HTTPClientRequest(url: input)
    request.method = HTTPMethod(rawValue: prepared.method)
    for (name, value) in prepared.headers.fields {
        request.headers.add(name: name, value: value)
    }
    if let body = prepared.body {
        request.body = .bytes(ByteBuffer(bytes: body))
    }
    let response: HTTPClientResponse
    do {
        // Browsers set no deadline either.
        response = try await client.execute(request, deadline: .distantFuture)
    } catch {
        throw .typeError("\(error)")
    }
    var headers = Headers()
    for header in response.headers {
        headers.append(header.name, header.value)
    }
    return Response(
        status: Int(response.status.code),
        statusText: response.status.reasonPhrase,
        headers: headers,
        url: response.history.last?.request.url ?? input,
        redirected: response.history.count > 1,
        body: ResponseBody(body: response.body)
    )
}

struct ResponseBody {
    let body: HTTPClientResponse.Body

    func bytes() async throws(FetchError) -> [UInt8] {
        do {
            return Array(try await body.collect(upTo: .max).readableBytesView)
        } catch {
            throw .typeError("\(error)")
        }
    }
}
#endif
