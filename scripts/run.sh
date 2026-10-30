#!/bin/sh

set -eu

# Builds a game and runs it: swift-game, the default, or the product named
# first. The other arguments go to swift build, as with build.sh:
# `run.sh shooter -c release` runs a release build of the shooter.

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
product=swift-game
if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then
    product=$1
    shift
fi

"$repository_root/scripts/build.sh" --product "$product" "$@"
bin_path=$(swift build --package-path "$repository_root" "$@" --show-bin-path)
exec "$bin_path/$product"
