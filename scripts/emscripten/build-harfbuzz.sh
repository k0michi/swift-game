#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
dependency_directory="$repository_root/.build/dependencies/emscripten/harfbuzz"
build_directory="$dependency_directory/cmake-build"

# The same HarfBuzz commit as the native build, compiled by emcc.
emcmake cmake \
    -G Ninja \
    -S "$repository_root/cmake/HarfBuzz" \
    -B "$build_directory" \
    -DCMAKE_BUILD_TYPE=Release \
    -DHARFBUZZ_METADATA_DIRECTORY="$dependency_directory"

cmake --build "$build_directory" --config Release --parallel
