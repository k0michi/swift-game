import BuildSystem
import Foundation

// The libraries swift-game's Swift targets are built against. Each becomes
// a pkg-config file of the same name for SwiftPM.
let sdl = CMakeArtifact(
    "swift-game-sdl3",
    source: GitSource("https://github.com/libsdl-org/SDL.git", commit: "fa2c02bb6e21974a89ea9824bc53c9932abe5f9c"),
    cacheVariables: [
        "SDL_SHARED": "OFF",
        "SDL_STATIC": "ON",
        "SDL_DEPS_SHARED": "OFF",
        // With dependencies linked rather than loaded, SDL would link the
        // libusb of whichever machine builds it. HIDAPI uses the OS's own
        // APIs without it on macOS and Windows.
        "SDL_HIDAPI_LIBUSB": "OFF",
        "SDL_INSTALL": "OFF",
        "SDL_TEST_LIBRARY": "OFF",
        "SDL_TESTS": "OFF",
        "SDL_EXAMPLES": "OFF",
    ],
    targets: ["SDL3::SDL3-static"]
)

// Dawn's backend for the host's graphics API.
#if os(macOS)
private let dawnBackends = ["DAWN_ENABLE_METAL": "ON", "DAWN_ENABLE_VULKAN": "OFF", "DAWN_ENABLE_D3D12": "OFF", "DAWN_ENABLE_OPENGLES": "OFF"]
#elseif os(Windows)
private let dawnBackends = ["DAWN_ENABLE_METAL": "OFF", "DAWN_ENABLE_VULKAN": "OFF", "DAWN_ENABLE_D3D12": "ON", "DAWN_ENABLE_OPENGLES": "OFF"]
#else
private let dawnBackends = ["DAWN_ENABLE_METAL": "OFF", "DAWN_ENABLE_VULKAN": "ON", "DAWN_ENABLE_D3D12": "OFF", "DAWN_ENABLE_OPENGLES": "ON"]
#endif

let dawn = CMakeArtifact(
    "swift-game-dawn",
    source: GitSource("https://dawn.googlesource.com/dawn", commit: "9a18acddc494a7cf5d3aed4bce81eb351ca59904"),
    cacheVariables: [
        "BUILD_SHARED_LIBS": "OFF",
        "DAWN_BUILD_MONOLITHIC_LIBRARY": "STATIC",
        "DAWN_BUILD_PROTOBUF": "OFF",
        "DAWN_BUILD_SAMPLES": "OFF",
        "DAWN_BUILD_TESTS": "OFF",
        "DAWN_ENABLE_INSTALL": "OFF",
        "DAWN_USE_GLFW": "OFF",
        "DAWN_FETCH_DEPENDENCIES": "ON",
        "TINT_BUILD_CMD_TOOLS": "OFF",
        "TINT_BUILD_IR_BINARY": "OFF",
        "TINT_BUILD_SAMPLES": "OFF",
        "TINT_BUILD_TESTS": "OFF",
    ].merging(dawnBackends) { $1 },
    targets: ["dawn::webgpu_dawn"],
    languages: ["C", "CXX"],
    platforms: [.host]
)

// Emdawnwebgpu implements webgpu.h on the browser's WebGPU. This release is
// built from 8 commits after the Dawn commit above, with no change to
// webgpu.h in between, so both share the Swift wrapper. Its C++ part and
// JavaScript come in when linking, through the port file.
let emdawnwebgpu = ArchiveArtifact(
    "swift-game-dawn",
    url: "https://github.com/google/dawn/releases/download/v20260916.214021/emdawnwebgpu_pkg-v20260916.214021.zip",
    sha256: "d9bdb0e11d221dac4028b87ecde0aeb1347a64760ccb41146b6ed883940b2d65",
    platforms: [.emscripten]
) { directory in
    let package = directory.appendingPathComponent("emdawnwebgpu_pkg")
    var usage = ArtifactUsage()
    usage.includeDirectories = [package.appendingPathComponent("webgpu/include").path]
    usage.linkerFlags = ["--use-port=\(package.appendingPathComponent("emdawnwebgpu.port.py").path)"]
    return usage
}

let artifacts: [any Artifact] = [sdl, dawn, emdawnwebgpu]

// Foundation for Emscripten builds, with the packages it builds with, checked
// out side by side as SWIFTCI_USE_LOCAL_DEPS expects. Apple platforms ship
// Foundation.
let foundationSources = [
    GitSource("https://github.com/apple/swift-collections.git", commit: "35a1edcb8ebd2bfe251d587f0b69e62af28f508c"),
    GitSource("https://github.com/swiftlang/swift-syntax.git", commit: "45eb43cda0ccc480c3011219d013f5e710672d8f"),
    GitSource("https://github.com/swiftlang/swift-foundation-icu.git", commit: "e8538d259340dd5b8c261f539f2693d094fe2dac"),
    GitSource(
        "https://github.com/swiftlang/swift-foundation.git",
        commit: "ca934a4122014e3f243057869637f108859b9176",
        patches: [patchesDirectory.appendingPathComponent("swift-foundation.patch")]
    ),
    GitSource(
        "https://github.com/swiftlang/swift-corelibs-foundation.git",
        commit: "28249ced079d8e7ec03b821c039bf9868738c3fc",
        patches: [patchesDirectory.appendingPathComponent("swift-corelibs-foundation.patch")]
    ),
]
