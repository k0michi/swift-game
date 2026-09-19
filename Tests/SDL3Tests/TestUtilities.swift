import Foundation

func withTemporaryFile<Result>(
    _ body: (URL) throws -> Result
) rethrows -> Result {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    return try body(url)
}
