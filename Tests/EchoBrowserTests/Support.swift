#if os(Emscripten)
import Echo

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

@MainActor
func expect(_ error: WebAudioError, _ message: String, _ body: () throws -> Void) {
    do {
        try body()
        fail("\(message): no error, expected \(error)")
    } catch let thrown as WebAudioError {
        expect(thrown == error, "\(message): \(thrown), expected \(error)")
    } catch {
        fail("\(message): \(error)")
    }
}

func isClose(_ value: Float, _ expected: Float, tolerance: Float = 1e-4) -> Bool {
    abs(value - expected) <= tolerance
}

@MainActor
func finish() {
    print(failures == 0 ? "All tests passed" : "\(failures) test(s) failed")
}
#endif
