#!/bin/sh

set -eu

# Downloads Noto Sans JP into the directory given, where the games are built:
# the same font as the native build.

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
build_directory="$repository_root/.build/dependencies/emscripten/noto-sans-jp/cmake-build"

cmake \
    -G Ninja \
    -S "$repository_root/cmake/NotoSansJP" \
    -B "$build_directory" \
    -DNOTO_SANS_JP_DESTINATION="$1"
