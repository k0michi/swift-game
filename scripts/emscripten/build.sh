#!/bin/sh

set -eu

# Builds a game for the browser into
# .build/wasm32-unknown-emscripten/<configuration>/<product>.html.
#
# Usage: build.sh [configuration] [product]
#
# The product is swift-game, the default, shooter, pong, or text.

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
configuration=${1:-debug}
product=${2:-swift-game}

case "$product" in
swift-game) target=SwiftGame ;;
shooter) target=Shooter ;;
pong) target=Pong ;;
text) target=Text ;;
*)
    echo "Unknown product $product" >&2
    exit 1
    ;;
esac

"$script_directory/build-sdl.sh"
"$script_directory/build-dawn.sh"
"$script_directory/build-stb.sh"
"$script_directory/build-freetype.sh"
"$script_directory/build-harfbuzz.sh"
bin_path=$("$script_directory/swift-build.sh" --configuration "$configuration" --show-bin-path | tail -n 1)
"$script_directory/../generate-build-info.sh" "$bin_path"
"$script_directory/build-noto-sans-jp.sh" "$bin_path"
"$script_directory/swift-build.sh" --configuration "$configuration" --target "$target"
"$script_directory/link.sh" "$product" "$configuration"
