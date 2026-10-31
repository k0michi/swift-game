import Foundation
import GameToolkit
import SystemPackage
import Testing

@Suite("writeFile")
struct FileWriteTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("FileWriteTests-\(UUID().uuidString)")

    @Test
    func writesAndReplacesFiles() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("file").path

        try await writeFile(Array(repeating: 7, count: 100), to: FilePath(path))
        #expect(FileManager.default.contents(atPath: path) == Data(repeating: 7, count: 100))
        // A shorter write leaves nothing of the longer one.
        try await writeFile([1, 2, 3], to: FilePath(path))
        #expect(FileManager.default.contents(atPath: path) == Data([1, 2, 3]))
    }

    @Test
    func failsWhereItCannotWrite() async {
        await #expect(throws: Errno.noSuchFileOrDirectory) {
            try await writeFile([1], to: FilePath(directory.appendingPathComponent("missing/file").path))
        }
    }
}
