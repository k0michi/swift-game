#!/bin/sh

set -eu

# Builds the game for the browser into
# .build/wasm32-unknown-emscripten/<configuration>/swift-game.html.
#
# Usage: build.sh [configuration]

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
configuration=${1:-debug}

"$script_directory/fetch-foundation.sh"
"$script_directory/build-sdl.sh"
"$script_directory/build-dawn.sh"
"$script_directory/swift-build.sh" --configuration "$configuration" --target SwiftGame
"$script_directory/link.sh" swift-game "$configuration"
