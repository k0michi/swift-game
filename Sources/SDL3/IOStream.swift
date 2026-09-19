import CSDL3
import Foundation

// SDL_IOStream
public final class IOStream: @unchecked Sendable {
    private let lock = NSLock()
    private var pointer: OpaquePointer?

    fileprivate init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    func withPointer<Result>(
        _ body: (OpaquePointer) throws -> Result
    ) throws -> Result {
        lock.lock()
        defer { lock.unlock() }
        guard let pointer else {
            throw SDLError(operation: "SDL_IOStream", message: "IO stream is closed")
        }
        return try body(pointer)
    }

    func takePointer() throws -> OpaquePointer {
        lock.lock()
        defer { lock.unlock() }
        guard let pointer else {
            throw SDLError(operation: "SDL_IOStream", message: "IO stream is closed")
        }
        self.pointer = nil
        return pointer
    }

    deinit {
        if let pointer {
            // SDL_CloseIO
            _ = SDL_CloseIO(pointer)
        }
    }
}

// SDL_IOFromFile
public func ioFromFile(file: String, mode: String) throws -> IOStream {
    guard let pointer = SDL_IOFromFile(file, mode) else {
        throw SDLError(operation: "SDL_IOFromFile")
    }
    return IOStream(pointer: pointer)
}
