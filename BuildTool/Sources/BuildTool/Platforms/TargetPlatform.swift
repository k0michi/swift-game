import BuildDescription
import Foundation

/// What building for one platform takes that building for another does not.
/// The rest of BuildTool is the same for every platform, so adding one is
/// adding a type that conforms to this, in a file of its own, and its case to
/// `targetPlatform(for:options:)`.
protocol TargetPlatform {
    var platform: Platform { get }

    /// The command that configures a CMake project for the platform, from the
    /// `arguments` that every platform's has, beginning with "cmake": with its
    /// compilers, or its toolchain.
    func cmakeConfigureCommand(_ arguments: [String], build: Build) throws -> [String]

    /// The words of a CMake link command's fragment, such as
    /// ["-framework", "Cocoa"] or ["libfreetype.a"], as swiftc or the
    /// platform's own link takes them. `resolve` makes a path absolute.
    func linkerFlags(fromFragment words: [String], resolve: (String) -> String) -> [String]

    /// What swift build and swift test take besides their own arguments.
    var swiftArguments: [String] { get }

    /// The environment swift build and swift test run in.
    func swiftEnvironment() throws -> [String: String]

    /// Builds `executables`, of `generated`, with `swift`.
    func buildExecutables(_ executables: [Target], generated: Generated, swift: SwiftPM) throws

    /// Runs the product built as `product` with `swift`.
    func run(product: String, swift: SwiftPM) throws
}

extension TargetPlatform {
    var swiftArguments: [String] { [] }

    func swiftEnvironment() throws -> [String: String] { [:] }

    // SwiftPM builds and links the products.
    func buildExecutables(_ executables: [Target], generated: Generated, swift: SwiftPM) throws {
        let products = executables.flatMap { ["--product", $0.product ?? $0.name] }
        try BuildTool.run(swift.command("build", products), environment: swiftEnvironment())
    }

    func run(product: String, swift: SwiftPM) throws {
        try BuildTool.run([try swift.binPath().appendingPathComponent(executableName(product)).path])
    }
}

/// The platform's own type.
func targetPlatform(for platform: Platform, options: Options) throws -> any TargetPlatform {
    switch platform {
    case .macOS: MacOS()
    case .linux: Linux()
    case .windows: Windows()
    case .emscripten: try Emscripten(options: options)
    }
}

/// The compilers of the Swift toolchain on the PATH, for CMake.
func toolchainCompilers(c: String, cxx: String) throws -> [String] {
    let bin = try executable(named: "swiftc").deletingLastPathComponent()
    return [
        "-DCMAKE_C_COMPILER=\(bin.appendingPathComponent(c).path)",
        "-DCMAKE_CXX_COMPILER=\(bin.appendingPathComponent(cxx).path)",
    ]
}

/// Whether the word at `index` is the value of the flag before it, such as
/// the framework after -framework, or what -Xlinker hands the linker, which
/// stays as it is.
func isFlagValue(_ words: [String], at index: Int) -> Bool {
    index > 0 && ["-framework", "-Xlinker"].contains(words[index - 1])
}

/// A linker flag for the C compiler's driver, "-Wl,a,b", as swiftc takes it.
func xlinkerFlags(_ word: String) -> [String] {
    word.dropFirst(4).split(separator: ",").flatMap { ["-Xlinker", String($0)] }
}
