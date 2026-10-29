#!/bin/sh

set -eu

# Writes what is being built into Sources/CBuildInfo, for the game to show.
# Builds run it first. It leaves the file as it is when nothing changed, so
# that nothing is compiled again.

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=$(git -C "$repository_root" describe --tags --always --dirty 2>/dev/null || echo unknown)
header="$repository_root/Sources/CBuildInfo/BuildInfo.generated.h"
contents="#define BUILD_INFO_VERSION \"$version\""

if [ ! -f "$header" ] || [ "$(cat "$header")" != "$contents" ]; then
    printf '%s\n' "$contents" > "$header"
fi
