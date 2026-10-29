#if os(Emscripten)
import CEmscripten
#endif

// Suspends until the next frame should be drawn. In the browser that is the
// next animation frame: the jobs it resumes run inside the
// requestAnimationFrame callback, so what they draw is in that frame. On the
// desktop presenting waits for the display, so this only lets other jobs run.
// There the caller needs to run under runMain.
public func nextFrame() async {
    #if os(Emscripten)
    await withUnsafeContinuation { continuation in
        let resumption = Unmanaged.passRetained(Resumption(continuation)).toOpaque()
        emscripten_request_animation_frame({ _, resumption in
            Unmanaged<Resumption>.fromOpaque(resumption!).takeRetainedValue().continuation.resume()
            BrowserExecutor.shared.drain()
            return false
        }, resumption)
    }
    #else
    await Task.yield()
    #endif
}

#if os(Emscripten)
private final class Resumption {
    let continuation: UnsafeContinuation<Void, Never>

    init(_ continuation: UnsafeContinuation<Void, Never>) {
        self.continuation = continuation
    }
}
#endif
