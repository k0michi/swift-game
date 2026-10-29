#!/bin/sh

set -eu

# Builds the game and runs it. The arguments go to swift build, as with
# build.sh: `run.sh -c release` runs a release build.

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

"$repository_root/scripts/build.sh" --product swift-game "$@"
bin_path=$(swift build --package-path "$repository_root" "$@" --show-bin-path)
exec "$bin_path/swift-game"
