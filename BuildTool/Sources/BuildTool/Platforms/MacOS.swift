import BuildDescription

/// macOS, with the Swift toolchain's clang, for the deployment target that
/// Build.swift names.
struct MacOS: TargetPlatform {
    var platform: Platform { .macOS }

    func cmakeConfigureCommand(_ arguments: [String], build: Build) throws -> [String] {
        arguments + (try toolchainCompilers(c: "clang", cxx: "clang++"))
            + (build.macOSDeploymentTarget.map { ["-DCMAKE_OSX_DEPLOYMENT_TARGET=\($0)"] } ?? [])
    }

    func linkerFlags(fromFragment words: [String], resolve: (String) -> String) -> [String] {
        words.indices.flatMap { index -> [String] in
            let word = words[index]
            if word.hasPrefix("-Wl,") {
                return xlinkerFlags(word)
            }
            return [word.hasPrefix("-") || isFlagValue(words, at: index) ? word : resolve(word)]
        }
    }
}
