#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_directory="$repository_root/.build/dependencies/sdl3/cmake-build"
install_directory="$repository_root/.build/dependencies/sdl3/install"
swift_bin_directory=$(dirname "$(command -v swiftc)")

set -- \
    --fresh \
    -G Ninja \
    -S "$repository_root" \
    -B "$build_directory" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$install_directory" \
    -DCMAKE_C_COMPILER="$swift_bin_directory/clang" \
    -DCMAKE_CXX_COMPILER="$swift_bin_directory/clang++"

if [ "$(uname -s)" = "Darwin" ]; then
    set -- "$@" -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0
fi

cmake "$@"

cmake --build "$build_directory" --config Release --parallel
cmake --install "$build_directory" --config Release

cmake \
    --fresh \
    -G Ninja \
    -S "$repository_root/cmake/ExtractSDLTarget" \
    -B "$repository_root/.build/dependencies/sdl3/metadata" \
    -DCMAKE_PREFIX_PATH="$install_directory" \
    -DOUTPUT_DIRECTORY="$repository_root/.build/dependencies/sdl3" \
    -DCMAKE_C_COMPILER="$swift_bin_directory/clang" \
    -DCMAKE_BUILD_TYPE=Release
