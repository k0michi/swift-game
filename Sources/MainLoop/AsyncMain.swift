/// A program whose main is `run`, which can await on every platform: a
/// `@main` type conforms to it and gets the `main` that the platform needs.
/// Its module imports MainLoop with `@_spi(ExperimentalCustomExecutors)`, for
/// Swift to find the executor that the browser needs.
@MainActor
public protocol AsyncMain {
    static func run() async throws
}

#if os(Emscripten)
    extension AsyncMain {
        // The browser's event loop runs the main actor's jobs, between frames.
        @_spi(ExperimentalCustomExecutors) public typealias DefaultExecutorFactory = BrowserExecutorFactory

        public static func main() async throws {
            try await run()
        }
    }
#else
    extension AsyncMain {
        public static func main() {
            runMain(run)
        }
    }
#endif
