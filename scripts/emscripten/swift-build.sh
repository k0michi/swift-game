#!/bin/sh

set -eu

# swift build for wasm32-unknown-emscripten, with the arguments passed on.
. "$(dirname -- "$0")/env.sh"
swift_build "$@"
