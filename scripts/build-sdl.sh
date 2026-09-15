#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_directory="$repository_root/Dependencies/SDL"
build_directory="$repository_root/.build/dependencies/sdl3/build"
install_directory="$repository_root/.build/dependencies/sdl3/install"

if [ ! -f "$source_directory/CMakeLists.txt" ]; then
    echo "SDL submodule is missing. Run: git submodule update --init --recursive" >&2
    exit 1
fi

set -- \
    -S "$source_directory" \
    -B "$build_directory" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$install_directory" \
    -DSDL_SHARED=OFF \
    -DSDL_STATIC=ON \
    -DSDL_INSTALL=ON \
    -DSDL_TEST_LIBRARY=OFF \
    -DSDL_TESTS=OFF \
    -DSDL_EXAMPLES=OFF \
    -DSDL_INSTALL_DOCS=OFF

if [ "$(uname -s)" = "Darwin" ]; then
    set -- "$@" -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0
fi

cmake "$@"

cmake --build "$build_directory" --config Release --parallel
cmake --install "$build_directory" --config Release

cmake \
    -S "$repository_root/cmake/ExtractSDLTarget" \
    -B "$repository_root/.build/dependencies/sdl3/metadata" \
    -DSDL3_DIR="$install_directory/lib/cmake/SDL3" \
    -DOUTPUT_DIRECTORY="$repository_root/.build/dependencies/sdl3" \
    -DCMAKE_BUILD_TYPE=Release
