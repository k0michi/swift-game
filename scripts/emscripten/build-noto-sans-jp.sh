#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
dependency_directory="$repository_root/.build/dependencies/emscripten/noto-sans-jp"
build_directory="$dependency_directory/cmake-build"

# The same font as the native build.
cmake \
    -G Ninja \
    -S "$repository_root/cmake/NotoSansJP" \
    -B "$build_directory" \
    -DNOTO_SANS_JP_METADATA_DIRECTORY="$dependency_directory"
