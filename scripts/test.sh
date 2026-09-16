#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

"$repository_root/scripts/build-sdl.sh"

SDL_VIDEODRIVER=dummy \
SDL_AUDIODRIVER=dummy \
swift test --package-path "$repository_root" "$@"
