// Echo's Web Audio implementation, run in headless Chromium by
// scripts/emscripten/test-browser.sh. The tests run one after another on the
// main actor and print "All tests passed" or "<n> test(s) failed".
#if os(Emscripten)
import MainLoop

runMainLoop {
    for (name, test) in tests {
        do {
            try await test()
        } catch {
            fail("\(name) threw \(error)")
        }
    }
    finish()
}
#else
print("EchoBrowserTests run in the browser: scripts/emscripten/test-browser.sh")
#endif
