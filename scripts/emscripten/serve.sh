#!/bin/sh

set -eu

# Builds the game for the browser and serves it at
# http://localhost:$PORT/swift-game.html (8000 by default).
#
# Usage: serve.sh [configuration]

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
configuration=${1:-debug}
port=${PORT:-8000}

"$script_directory/build.sh" "$configuration"

echo "Serving http://localhost:$port/swift-game.html"
exec python3 -m http.server "$port" --bind 127.0.0.1 \
    --directory "$repository_root/.build/wasm32-unknown-emscripten/$configuration"
