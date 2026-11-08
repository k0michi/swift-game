import MainLoop

/// Lets long work on the browser's one thread give way to it now and then,
/// so that the page stays alive. Elsewhere there is nothing to give way to.
@MainActor
struct Breather {
    private let clock = ContinuousClock()
    private var last = ContinuousClock.now
    private static let longest = Duration.milliseconds(12)

    /// Gives way to the browser, if working has gone on for long.
    mutating func breathe() async {
        #if os(Emscripten)
            if clock.now - last > Self.longest {
                await nextFrame()
                last = clock.now
            }
        #endif
    }
}
