import CSDL3

// SDL_Mutex
/// A lock that SDL makes for its platform, which needs nothing else on any.
public final class Mutex: @unchecked Sendable {
    private let pointer: OpaquePointer

    // SDL_CreateMutex
    public init() {
        guard let pointer = SDL_CreateMutex() else {
            fatalError("SDL_CreateMutex failed: \(String(cString: SDL_GetError()))")
        }
        self.pointer = pointer
    }

    // SDL_DestroyMutex
    deinit {
        SDL_DestroyMutex(pointer)
    }

    // SDL_LockMutex
    public func lock() {
        SDL_LockMutex(pointer)
    }

    // SDL_UnlockMutex
    public func unlock() {
        SDL_UnlockMutex(pointer)
    }
}
