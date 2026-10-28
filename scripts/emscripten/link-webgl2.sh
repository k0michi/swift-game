#!/bin/sh

set -eu

# Links the game against a build of the WebGL 2 fork of Dawn instead of
# Emdawnwebgpu, into
# .build/wasm32-unknown-emscripten/<configuration>/webgl2/swift-game.html.
# The fork is the webgl2 branch of https://github.com/k0michi/dawn, and its
# .github/webgl2/build.sh makes the build directory. It must be built from the
# same Dawn commit as Emdawnwebgpu in build-dawn.sh, whose headers the game is
# compiled against.
#
# Run build.sh with the same configuration first.
#
# Usage: link-webgl2.sh <Dawn build directory> [configuration]

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
dawn_build=$(CDPATH= cd -- "$1" && pwd -P)
configuration=${2:-debug}
library="$dawn_build/src/dawn/native/libwebgpu_dawn.a"
if [ ! -f "$library" ]; then
    echo "No $library" >&2
    exit 1
fi

. "$script_directory/env.sh"
bin_directory=$(swift_build --configuration "$configuration" --show-bin-path)
flags_directory="$repository_root/.build/dependencies/emscripten/dawn-webgl2"
mkdir -p "$flags_directory" "$bin_directory/webgl2"
printf '%s\n' \
    "$library" \
    -sMIN_WEBGL_VERSION=2 \
    -sMAX_WEBGL_VERSION=2 \
    -sGL_ENABLE_GET_PROC_ADDRESS \
    -sSTACK_SIZE=1MB \
    > "$flags_directory/linker-flags.txt"

SWIFT_GAME_DAWN_LINKER_FLAGS="$flags_directory/linker-flags.txt" \
    SWIFT_GAME_OUTPUT_DIRECTORY="$bin_directory/webgl2" \
    "$script_directory/link.sh" swift-game "$configuration"
