import BuildDescription

/// Linux, with the Swift toolchain's clang.
struct Linux: TargetPlatform {
    var platform: Platform { .linux }

    func cmakeConfigureCommand(_ arguments: [String], build: Build) throws -> [String] {
        arguments + (try toolchainCompilers(c: "clang", cxx: "clang++"))
    }

    // swiftc takes -pthread as the library it is.
    func linkerFlags(fromFragment words: [String], resolve: (String) -> String) -> [String] {
        words.indices.flatMap { index -> [String] in
            let word = words[index]
            if word.hasPrefix("-Wl,") {
                return xlinkerFlags(word)
            }
            if word == "-pthread" {
                return ["-lpthread"]
            }
            return [word.hasPrefix("-") || isFlagValue(words, at: index) ? word : resolve(word)]
        }
    }
}
