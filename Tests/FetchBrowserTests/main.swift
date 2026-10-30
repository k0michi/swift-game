// Fetch on the browser's fetch, run in headless Chromium by
// scripts/emscripten/test-browser.sh, which serves the page and the files
// next to it. The tests run one after another on the main actor and print
// "All tests passed" or "<n> test(s) failed".
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
print("FetchBrowserTests run in the browser: scripts/emscripten/test-browser.sh")
#endif
