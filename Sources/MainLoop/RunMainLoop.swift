#if os(Emscripten)
import CEmscripten
@_spi(ExperimentalCustomExecutors) import _Concurrency
#endif
#if canImport(Dispatch)
import Dispatch
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(ucrt)
import ucrt
#elseif os(Emscripten)
import EmscriptenLibc
#endif

// Runs `body` on the main actor and does not return: the process exits when
// it finishes, with status 1 if it throws. Call it from a synchronous main.
//
// An `async main` would do the same on the desktop, but in the browser its
// main executor has to give the thread back to the event loop. Swift only
// picks up a custom main executor for `async main` behind a feature that is
// not yet available, so the executors are set here before anything runs.
public func runMainLoop(_ body: @escaping @MainActor () async throws -> Void) -> Never {
    #if os(Emscripten)
    _createExecutors(factory: BrowserExecutorFactory.self)
    #endif
    Task { @MainActor in
        do {
            try await body()
        } catch {
            print("Error: \(error)")
            exit(1)
        }
        exit(0)
    }
    #if os(Emscripten)
    try! BrowserExecutor.shared.run()
    fatalError("BrowserExecutor.run() returned")
    #else
    dispatchMain()
    #endif
}
