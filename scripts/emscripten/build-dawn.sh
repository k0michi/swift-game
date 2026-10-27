#!/bin/sh

set -eu

# Emdawnwebgpu implements webgpu.h on the browser's WebGPU. This release is
# built from 8 commits after the Dawn commit in cmake/Dawn/CMakeLists.txt, with
# no change to webgpu.h in between, so both builds share the Swift wrapper.
version=v20260916.214021
sha256=d9bdb0e11d221dac4028b87ecde0aeb1347a64760ccb41146b6ed883940b2d65

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
dependency_directory="$repository_root/.build/dependencies/emscripten/dawn"
package_directory="$dependency_directory/emdawnwebgpu_pkg"
archive="$dependency_directory/emdawnwebgpu_pkg-$version.zip"

mkdir -p "$dependency_directory"
if [ "$(cat "$package_directory/VERSION.txt" 2>/dev/null || true)" != "$version" ]; then
    curl -fsSL -o "$archive" \
        "https://github.com/google/dawn/releases/download/$version/emdawnwebgpu_pkg-$version.zip"
    echo "$sha256  $archive" | shasum -a 256 -c -
    rm -rf "$package_directory"
    unzip -q "$archive" -d "$dependency_directory"
    rm "$archive"
fi

# The headers come before Emscripten's own, older webgpu.h. The port compiles
# its C++ and adds its JavaScript when linking.
printf '%s\n' "-I$package_directory/webgpu/include" > "$dependency_directory/compiler-flags.txt"
printf '%s\n' "--use-port=$package_directory/emdawnwebgpu.port.py" > "$dependency_directory/linker-flags.txt"
