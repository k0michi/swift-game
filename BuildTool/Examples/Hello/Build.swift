import BuildDescription

let sdl = CMakeProject(
    "sdl",
    git: "https://github.com/libsdl-org/SDL.git",
    revision: "fa2c02bb6e21974a89ea9824bc53c9932abe5f9c",
    options: [
        "SDL_SHARED": "OFF", "SDL_STATIC": "ON", "SDL_TEST_LIBRARY": "OFF", "SDL_TESTS": "OFF",
        "SDL_EXAMPLES": "OFF",
        // Without X11 or Wayland, which the example does not open a window on.
        "SDL_UNIX_CONSOLE_BUILD": platform == .linux ? "ON" : "OFF",
    ],
    targets: ["SDL3-static"])

let freeType = CMakeProject(
    "freetype",
    git: "https://gitlab.freedesktop.org/freetype/freetype.git",
    revision: "631ee12ce7693c9ba9ea33f0235da99218045420",  // VER-2-15-0
    options: [
        "FT_DISABLE_ZLIB": "ON", "FT_DISABLE_BZIP2": "ON", "FT_DISABLE_PNG": "ON",
        "FT_DISABLE_HARFBUZZ": "ON", "FT_DISABLE_BROTLI": "ON", "FT_DISABLE_HVF": "ON",
    ],
    targets: ["freetype"])

// HarfBuzz has no CMake project of its own to build harfbuzz.cc alone, so
// swift-game's is used. On Linux it needs the C++ library, which swiftc does
// not link and CMake does not say.
let harfBuzz = CMakeProject(
    "harfbuzz", path: "../../../cmake/HarfBuzz", targets: ["harfbuzz"],
    linkerFlags: platform == .linux ? ["-lstdc++"] : [])

let notoSansJP = Download(
    "NotoSansJP-Regular.otf",
    url: "https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/SubsetOTF/JP/NotoSansJP-Regular.otf",
    sha256: "dff723ba59d57d136764a04b9b2d03205544f7cd785a711442d6d2d085ac5073")

let build = Build(
    name: "Hello",
    macOSDeploymentTarget: "13.0",
    cmakeProjects: [sdl, freeType, harfBuzz],
    downloads: [notoSansJP],
    targets: [
        .target(name: "CSDL3", linking: [sdl.target("SDL3-static")]),
        .target(name: "CFreeType", linking: [freeType.target("freetype")]),
        .target(name: "CHarfBuzz", linking: [harfBuzz.target("harfbuzz")]),
        .executableTarget(
            name: "Hello", product: "hello", dependencies: ["CSDL3", "CFreeType", "CHarfBuzz"],
            // Emscripten's, for its link, which BuildTool does.
            linkerFlags: platform == .emscripten ? ["-sALLOW_MEMORY_GROWTH=1"] : [], assets: [notoSansJP]),
    ])
