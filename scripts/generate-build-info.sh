#!/bin/sh

set -eu

# Writes what is being built into Sources/CBuildInfo, for the game to show:
# the source's version, the Swift compiler's, and the target triple, which is
# the host's unless given, as the browser build gives its own. Builds run it
# first. It leaves the file as it is when nothing changed, so that nothing is
# compiled again.
#
# Usage: generate-build-info.sh [target triple]

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=$(git -C "$repository_root" describe --tags --always --dirty 2>/dev/null || echo unknown)
# The compiler the build uses, which the browser build lets SWIFT choose.
target_info=$("${SWIFT:-swift}" -print-target-info 2>/dev/null || true)
swift_version=$(printf '%s\n' "$target_info" | sed -n -E 's/.*"compilerVersion": ".*Swift version ([^ "]+).*/\1/p')
triple=${1:-$(printf '%s\n' "$target_info" | sed -n -E 's/.*"unversionedTriple": "([^"]+)".*/\1/p' | head -n 1)}
header="$repository_root/Sources/CBuildInfo/BuildInfo.generated.h"
contents="#define BUILD_INFO_VERSION \"$version\"
#define BUILD_INFO_SWIFT_VERSION \"${swift_version:-unknown}\"
#define BUILD_INFO_TRIPLE \"${triple:-unknown}\""

if [ ! -f "$header" ] || [ "$(cat "$header")" != "$contents" ]; then
    printf '%s\n' "$contents" > "$header"
fi
