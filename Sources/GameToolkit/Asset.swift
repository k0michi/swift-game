import SDL3

#if os(Emscripten)
    import CGameToolkitWeb
#else
    import Dispatch
#endif

/// The HTTP status of an asset the browser could not fetch, 0 if there was
/// no response.
public struct AssetError: Error, Equatable {
    public let path: String
    public let status: Int
}

/// Reads the file at `path`, relative to the executable's directory, or to the
/// page's URL in the browser, which fetches it.
public func readAsset(_ path: String) async throws -> [UInt8] {
    #if os(Emscripten)
        final class Reading {
            let path: String
            let continuation: CheckedContinuation<[UInt8], any Error>

            init(path: String, continuation: CheckedContinuation<[UInt8], any Error>) {
                self.path = path
                self.continuation = continuation
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            let reading = Unmanaged.passRetained(Reading(path: path, continuation: continuation))
            game_toolkit_web_fetch(path, reading.toOpaque()) { context, id, length, status in
                let reading = Unmanaged<Reading>.fromOpaque(context!).takeRetainedValue()
                guard id != 0 else {
                    reading.continuation.resume(throwing: AssetError(path: reading.path, status: Int(status)))
                    return
                }
                var bytes = [UInt8](repeating: 0, count: Int(length))
                bytes.withUnsafeMutableBufferPointer { game_toolkit_web_take(id, $0.baseAddress) }
                reading.continuation.resume(returning: bytes)
            }
        }
    #else
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try loadFile(file: getBasePath() + path) })
            }
        }
    #endif
}
