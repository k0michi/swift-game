#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
dependency_directory="$repository_root/.build/dependencies/stb"
build_directory="$dependency_directory/cmake-build"
swift_bin_directory=$(dirname "$(command -v swiftc)")

set -- \
    -G Ninja \
    -S "$repository_root/cmake/Stb" \
    -B "$build_directory" \
    -DCMAKE_BUILD_TYPE=Release \
    -DSTB_METADATA_DIRECTORY="$dependency_directory" \
    -DCMAKE_C_COMPILER="$swift_bin_directory/clang"

if [ "$(uname -s)" = "Darwin" ]; then
    set -- "$@" -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0
fi

cmake "$@"
cmake --build "$build_directory" --config Release --parallel
