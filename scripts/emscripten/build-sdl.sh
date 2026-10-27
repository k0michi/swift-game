#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
dependency_directory="$repository_root/.build/dependencies/emscripten/sdl3"
build_directory="$dependency_directory/cmake-build"
install_directory="$dependency_directory/install"

# The same SDL commit as the native build, compiled by emcc.
emcmake cmake \
    -G Ninja \
    -S "$repository_root" \
    -B "$build_directory" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$install_directory"

cmake --build "$build_directory" --config Release --parallel
cmake --install "$build_directory" --config Release

# emcmake's toolchain file restricts find_package to the Emscripten sysroot,
# so the install prefix is also searched as a root.
emcmake cmake \
    -G Ninja \
    -S "$repository_root/cmake/ExtractSDLTarget" \
    -B "$dependency_directory/metadata" \
    -DCMAKE_PREFIX_PATH="$install_directory" \
    -DCMAKE_FIND_ROOT_PATH="$install_directory" \
    -DOUTPUT_DIRECTORY="$dependency_directory" \
    -DCMAKE_BUILD_TYPE=Release
