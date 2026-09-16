#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
dependency_directory="$repository_root/.build/dependencies/dawn"
build_directory="$dependency_directory/cmake-build"
install_directory="$dependency_directory/install"
swift_bin_directory=$(dirname "$(command -v swiftc)")

set -- \
    -S "$repository_root/cmake/Dawn" \
    -B "$build_directory" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$install_directory" \
    -DDAWN_METADATA_DIRECTORY="$dependency_directory" \
    -DCMAKE_C_COMPILER="$swift_bin_directory/clang" \
    -DCMAKE_CXX_COMPILER="$swift_bin_directory/clang++"

if [ "$(uname -s)" = "Darwin" ]; then
    set -- "$@" -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0
fi

cmake "$@"
cmake --build "$build_directory" --config Release --parallel
cmake --install "$build_directory" --config Release
