#if os(Emscripten)
import Fetch

@MainActor private var failures = 0

@MainActor
func fail(_ message: String) {
    failures += 1
    print("FAIL \(message)")
}

@MainActor
func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
    if !condition { fail(message()) }
}

/// Expects `body` to fail with `error`, or with any FetchError when nil.
@MainActor
func expect(_ error: FetchError?, _ message: String, _ body: () async throws -> Void) async {
    do {
        try await body()
        fail("\(message): no error")
    } catch let thrown as FetchError {
        if let error { expect(thrown == error, "\(message): \(thrown), expected \(error)") }
    } catch {
        fail("\(message): \(error)")
    }
}

@MainActor
func finish() {
    print(failures == 0 ? "All tests passed" : "\(failures) test(s) failed")
}
#endif
