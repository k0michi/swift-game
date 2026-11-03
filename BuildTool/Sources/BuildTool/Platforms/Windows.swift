import BuildDescription

/// Windows, with the Swift toolchain's clang-cl.
struct Windows: TargetPlatform {
    var platform: Platform { .windows }

    func cmakeConfigureCommand(_ arguments: [String], build: Build) throws -> [String] {
        arguments + (try toolchainCompilers(c: "clang-cl.exe", cxx: "clang-cl.exe"))
    }

    // A library of the system, such as kernel32.lib, which the linker finds
    // by its name.
    func linkerFlags(fromFragment words: [String], resolve: (String) -> String) -> [String] {
        words.indices.map { index in
            let word = words[index]
            if word.hasPrefix("-") || isFlagValue(words, at: index) {
                return word
            }
            if word.hasSuffix(".lib"), !word.contains("/"), !word.contains("\\") {
                return "-l" + word.dropLast(4)
            }
            return resolve(word)
        }
    }
}
