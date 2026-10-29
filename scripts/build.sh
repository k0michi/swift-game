#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

"$repository_root/scripts/build-sdl.sh"
"$repository_root/scripts/build-dawn.sh"
# The manifest reads the dependencies' flags, which SwiftPM does not know
# about, so neither its cached manifest nor its build plans would see them
# change.
rm -f "$repository_root/.build/debug.yaml" "$repository_root/.build/release.yaml"
swift build --package-path "$repository_root" --manifest-cache none "$@"
