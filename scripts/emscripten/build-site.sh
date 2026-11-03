#!/bin/sh

set -eu

# Builds the games for the browser in release and lays them out as one site
# in the directory given: the bullet-dodging game at the top, the shooter at
# /shooter/, Pong at /pong/, and the text sample at /text/, beside its font.
#
# Usage: build-site.sh <directory>

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
site=$1
release="$repository_root/.build/wasm32-unknown-emscripten/release"

for game in swift-game shooter pong text; do
    "$script_directory/build.sh" release "$game"
    page="$site"
    if [ "$game" != swift-game ]; then page="$site/$game"; fi
    mkdir -p "$page"
    cp "$release/$game.js" "$release/$game.wasm" "$page/"
    cp "$release/$game.html" "$page/index.html"
done
cp "$release/NotoSansJP-Regular.otf" "$release/NotoSansJP-LICENSE.txt" "$site/text/"
