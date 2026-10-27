import Foundation

// What the artifacts and products are built for.
public enum Platform: String, CaseIterable, Sendable {
    // The machine running the build.
    case host
    // wasm32-unknown-emscripten, for browsers.
    case emscripten
}

// How CMake builds for a platform.
public struct Toolchain: Sendable {
    public let platform: Platform
    public let cmakeArguments: [String]

    // The host builds with the clang next to the Swift compiler, so that C,
    // C++ and Swift agree; Emscripten with the toolchain file of the emcc in
    // PATH.
    public static func resolve(_ platform: Platform, macOSDeploymentTarget: String) throws -> Toolchain {
        switch platform {
        case .host:
            let bin = try which("swiftc").deletingLastPathComponent()
            #if os(Windows)
            // clang-cl, for the MSVC ABI that Swift uses on Windows.
            let c = bin.appendingPathComponent("clang-cl.exe").path
            let cxx = c
            #else
            let c = bin.appendingPathComponent("clang").path
            let cxx = bin.appendingPathComponent("clang++").path
            #endif
            var arguments = ["-DCMAKE_C_COMPILER=\(c)", "-DCMAKE_CXX_COMPILER=\(cxx)"]
            #if os(macOS)
            arguments.append("-DCMAKE_OSX_DEPLOYMENT_TARGET=\(macOSDeploymentTarget)")
            #endif
            return Toolchain(platform: platform, cmakeArguments: arguments)
        case .emscripten:
            let root = try output("em-config", ["EMSCRIPTEN_ROOT"])
            return Toolchain(platform: platform, cmakeArguments: [
                "-DCMAKE_TOOLCHAIN_FILE=\(root)/cmake/Modules/Platform/Emscripten.cmake",
            ])
        }
    }
}
