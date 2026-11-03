import BuildDescription
import Foundation

/// Windows, with the Swift toolchain's clang-cl.
struct Windows: TargetPlatform {
    var platform: Platform { .windows }

    func cmakeConfigureCommand(_ arguments: [String], build: Build) throws -> [String] {
        arguments + (try toolchainCompilers(c: "clang-cl.exe", cxx: "clang-cl.exe"))
    }

    // A library named without a directory is the build's own, such as
    // SDL3-static.lib, when the build has it, and otherwise the system's,
    // such as kernel32.lib, which the linker finds by its name.
    func linkerFlags(fromFragment words: [String], resolve: (String) -> String) -> [String] {
        words.indices.map { index in
            let word = words[index]
            if word.hasPrefix("-") || isFlagValue(words, at: index) {
                return word
            }
            let path = resolve(word)
            if word.hasSuffix(".lib"), !FileManager.default.fileExists(atPath: path) {
                return "-l" + word.dropLast(4)
            }
            return path
        }
    }
}
