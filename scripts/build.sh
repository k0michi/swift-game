#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

"$repository_root/scripts/build-sdl.sh"
"$repository_root/scripts/build-dawn.sh"
swift build --package-path "$repository_root" "$@"
