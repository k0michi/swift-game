#!/bin/sh

set -eu

# Emdawnwebgpu implements webgpu.h on the browser's WebGPU. This release is
# built from the Dawn commit in cmake/Dawn/CMakeLists.txt, so both builds share
# the Swift wrapper. The WebGL 2 build (link-webgl2.sh) needs the same commit.
version=v20261026.205545
sha256=9a51035308ffbb39c33d1ea259dfd164c97a242d2da7ad29455e87c1dcf5e441

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
