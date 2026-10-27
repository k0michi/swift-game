# Settings shared by the Emscripten scripts. Source this file.
#
# SWIFT_EMSCRIPTEN_SDK names the installed Swift SDK for
# wasm32-unknown-emscripten. SWIFT_SDKS_PATH is where it is installed, when not
# in SwiftPM's default directory. SWIFT is the swift command to build with.

if [ -z "${SWIFT_EMSCRIPTEN_SDK:-}" ]; then
    echo "Set SWIFT_EMSCRIPTEN_SDK to the Swift SDK for wasm32-unknown-emscripten." >&2
    exit 1
fi

emscripten_scripts=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$emscripten_scripts/../.." && pwd)
export SWIFT="${SWIFT:-swift}"
export SWIFT_GAME_TARGET=emscripten
export SWIFTCI_USE_LOCAL_DEPS="$repository_root/.build/dependencies/emscripten/foundation"
if [ -z "${HOST_CC:-}" ]; then
    HOST_CC=$(command -v "${CC:-clang}")
    export HOST_CC
fi
export CC="$emscripten_scripts/cc.sh"

# swift build for the Emscripten SDK. The manifest reads files and the
# environment that SwiftPM does not track, so its cache is not used.
swift_build() {
    if [ -n "${SWIFT_SDKS_PATH:-}" ]; then
        set -- --swift-sdks-path "$SWIFT_SDKS_PATH" "$@"
    fi
    "$SWIFT" build --manifest-cache none --swift-sdk "$SWIFT_EMSCRIPTEN_SDK" "$@"
}

# Prints a path from the SDK's configuration, such as sdkRootPath.
swift_sdk_path() {
    if [ -n "${SWIFT_SDKS_PATH:-}" ]; then
        set -- "$1" --swift-sdks-path "$SWIFT_SDKS_PATH"
    fi
    key=$1
    shift
    "$SWIFT" sdk configure "$@" --show-configuration "$SWIFT_EMSCRIPTEN_SDK" wasm32-unknown-emscripten \
        | sed -n "s/^$key: //p"
}
