// Echo's Web Audio implementation, run in headless Chromium by
// `swift run --package-path Tools build test --platform emscripten`. The
// tests run one after another on the main actor and print "All tests passed"
// or "<n> test(s) failed".
#if os(Emscripten)
@_spi(ExperimentalCustomExecutors) import MainLoop

typealias DefaultExecutorFactory = BrowserExecutorFactory

for (name, test) in tests {
    do {
        try await test()
    } catch {
        fail("\(name) threw \(error)")
    }
}
finish()
#else
print("EchoBrowserTests run in the browser: swift run --package-path Tools build test --platform emscripten")
#endif
