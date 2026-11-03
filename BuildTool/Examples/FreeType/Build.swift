import BuildDescription

let freeType = CMakeProject(
    "freetype",
    git: "https://gitlab.freedesktop.org/freetype/freetype.git",
    revision: "631ee12ce7693c9ba9ea33f0235da99218045420",  // VER-2-15-0
    options: [
        "FT_DISABLE_ZLIB": "ON", "FT_DISABLE_BZIP2": "ON", "FT_DISABLE_PNG": "ON",
        "FT_DISABLE_HARFBUZZ": "ON", "FT_DISABLE_BROTLI": "ON", "FT_DISABLE_HVF": "ON",
    ],
    targets: ["freetype"])

let notoSansJP = Download(
    "NotoSansJP-Regular.otf",
    url: "https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/SubsetOTF/JP/NotoSansJP-Regular.otf",
    sha256: "dff723ba59d57d136764a04b9b2d03205544f7cd785a711442d6d2d085ac5073")

let build = Build(
    name: "FreeTypeExample",
    macOSDeploymentTarget: "13.0",
    cmakeProjects: [freeType],
    downloads: [notoSansJP],
    targets: [
        .target(name: "CFreeType", linking: [freeType.target("freetype")]),
        .executableTarget(name: "Hello", product: "hello", dependencies: ["CFreeType"], assets: [notoSansJP]),
    ])
