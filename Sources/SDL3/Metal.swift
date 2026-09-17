import CSDL3
import Interop

// SDL_MetalView
@MainActor
public final class MetalView {
    package let pointer: UnsafeMutableRawPointer
    private let window: Window

    fileprivate init(pointer: UnsafeMutableRawPointer, window: Window) {
        self.pointer = pointer
        self.window = window
    }

    isolated deinit {
        // SDL_Metal_DestroyView
        SDL_Metal_DestroyView(pointer)
    }
}

// SDL_Metal_CreateView
@MainActor
public func metalCreateView(window: Window) throws -> MetalView {
    guard let pointer = SDL_Metal_CreateView(window.cPointer) else {
        throw SDLError(operation: "SDL_Metal_CreateView")
    }
    return MetalView(pointer: pointer, window: window)
}

// SDL_Metal_GetLayer
@MainActor
public func metalGetLayer(view: MetalView) throws -> UnsafeLifetimeBoundRawPointer {
    guard let layer = SDL_Metal_GetLayer(view.pointer) else {
        throw SDLError(operation: "SDL_Metal_GetLayer")
    }
    return UnsafeLifetimeBoundRawPointer(layer, boundTo: view)
}
