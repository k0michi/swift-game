import Dawn
import Echo
import SDL3

#if !os(Emscripten)
    import EchoSDL3
#endif

// What differs between the platforms, so that games need not ask.

/// `flags` with the window flags that the platform needs too.
public func platformWindowFlags(_ flags: WindowFlags) -> WindowFlags {
    var flags = flags
    #if os(macOS)
        flags.insert(.metal)
    #endif
    return flags
}

/// The adapter to ask for: the platform's native graphics API. In a browser,
/// which may give WebGL 2, it asks only for compatibility mode, which WebGL 2
/// offers.
public func platformAdapterOptions() -> RequestAdapterOptions {
    #if os(macOS)
        RequestAdapterOptions(featureLevel: .core, backendType: .metal)
    #elseif os(Windows)
        RequestAdapterOptions(featureLevel: .core, backendType: .d3D12)
    #elseif os(Emscripten)
        RequestAdapterOptions(featureLevel: .compatibility, backendType: .undefined)
    #else
        RequestAdapterOptions(featureLevel: .core, backendType: .vulkan)
    #endif
}

/// An audio context that plays through SDL3, or through the browser's Web
/// Audio in a browser, where it stays suspended until a user gesture.
@MainActor
public func makeAudioContext(system: System) throws -> AudioContext {
    #if os(Emscripten)
        try AudioContext()
    #else
        try AudioContext(backend: SDLAudioOutputBackend(system: system, channelCount: 2))
    #endif
}

/// Whether audio waits for a user gesture to start, as in a browser.
public let audioWaitsForUserGesture: Bool = {
    #if os(Emscripten)
        true
    #else
        false
    #endif
}()
