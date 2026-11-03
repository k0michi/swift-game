import BuildDescription
import Foundation

/// Downloads `download` once, and returns where it is, checked against its
/// SHA-256.
func fetch(_ download: Download, in work: URL) throws -> URL {
    let directory = work.appendingPathComponent("downloads").appendingPathComponent(download.sha256)
    let file = directory.appendingPathComponent(download.name)
    if FileManager.default.fileExists(atPath: file.path) {
        return file
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let partial = directory.appendingPathComponent(download.name + ".part")
    try run(["curl", "--fail", "--location", "--silent", "--show-error", "--output", partial.path, download.url])
    // CMake, which the build needs anyway, hashes it on every platform.
    let sha256 = try output(of: ["cmake", "-E", "sha256sum", partial.path]).split(separator: " ").first ?? ""
    guard sha256 == download.sha256 else {
        try? FileManager.default.removeItem(at: partial)
        throw BuildToolError("\(download.url) has the SHA-256 \(sha256), not \(download.sha256)")
    }
    try FileManager.default.moveItem(at: partial, to: file)
    return file
}
