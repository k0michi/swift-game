#if !os(Emscripten)
    import Dispatch
    import SystemPackage

    // Files are written synchronously, so writes run one after another on a
    // thread of their own, for the caller not to wait on the disk.
    private let fileWrites = DispatchQueue(label: "GameToolkit.fileWrites", qos: .utility)

    /// Writes `bytes` to the file at `path`, creating it or replacing what
    /// it held, on the thread for file writes. Writes finish in the order
    /// they were asked for.
    public func writeFile(_ bytes: [UInt8], to path: FilePath) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            fileWrites.async {
                do {
                    let file = try FileDescriptor.open(
                        path, .writeOnly, options: [.create, .truncate], permissions: [.ownerReadWrite, .groupRead, .otherRead])
                    try file.closeAfter {
                        _ = try file.writeAll(bytes)
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
#endif
