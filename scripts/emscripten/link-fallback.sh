#!/bin/sh

set -eu

# Links the game into one wasm that draws with the browser's WebGPU when it has
# a compatibility-mode adapter, and with the WebGL 2 fork of Dawn otherwise,
# into .build/wasm32-unknown-emscripten/<configuration>/fallback/swift-game.html.
#
# Emdawnwebgpu's wgpu* functions are renamed (fallback/make-emdawn.py) so that
# it links next to dawn::native, without dawn::native's own wgpu* functions.
# The wgpu* functions of Dawn's dawn_proc call through a table, which
# fallback/selector.cpp points at either one before main(), as
# fallback/pre.js chose. ?backend=webgpu or ?backend=webgl2 in the page's URL
# forces one.
#
# The fork is the webgl2 branch of https://github.com/k0michi/dawn, and its
# .github/webgl2/build.sh makes the build directory, with dawn::native and
# dawn_proc built from the same commit. It must be the Dawn commit of
# Emdawnwebgpu in build-dawn.sh.
#
# Run build.sh with the same configuration first.
#
# Usage: link-fallback.sh <Dawn build directory> [configuration]

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
dawn_build=$(CDPATH= cd -- "$1" && pwd -P)
configuration=${2:-debug}
native="$dawn_build/src/dawn/native/libwebgpu_dawn.a"
proc="$dawn_build/src/dawn/libdawn_proc.a"
for library in "$native" "$proc"; do
    if [ ! -f "$library" ]; then
        echo "No $library" >&2
        exit 1
    fi
done
dawn_source=$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "$dawn_build/CMakeCache.txt")

. "$script_directory/env.sh"
bin_directory=$(swift_build --configuration "$configuration" --show-bin-path)
work="$repository_root/.build/dependencies/emscripten/dawn-fallback"
package="$repository_root/.build/dependencies/emscripten/dawn/emdawnwebgpu_pkg"
mkdir -p "$work" "$bin_directory/fallback"

# dawn::native without its wgpu* functions, which dawn_proc defines instead.
cp "$native" "$work/libdawn_native.a"
"${EMAR:-emar}" d "$work/libdawn_native.a" webgpu_dawn_native_proc.cpp.o

python3 "$script_directory/fallback/make-emdawn.py" "$package" "$work/emdawn"
compile="${EMXX:-em++} -std=c++20 -O2 -fno-exceptions"
dawn_includes="-DDAWN_EMSCRIPTEN_NATIVE -I$dawn_source/include -I$dawn_build/gen/include"
$compile -DNDEBUG -isystem "$package/webgpu/include" -include "$work/emdawn/rename.h" \
    -c "$package/webgpu/src/webgpu.cpp" -o "$work/emdawn/webgpu.o"
$compile $dawn_includes -include "$work/emdawn/rename.h" \
    -c "$work/emdawn/emdawn_procs.cpp" -o "$work/emdawn/emdawn_procs.o"
$compile $dawn_includes -c "$script_directory/fallback/selector.cpp" -o "$work/selector.o"

# link.sh passes paths to swiftc as inputs, so options take their paths after =.
printf '%s\n' \
    "$work/selector.o" \
    "$work/emdawn/emdawn_procs.o" \
    "$work/emdawn/webgpu.o" \
    "$proc" \
    "$work/libdawn_native.a" \
    "--js-library=$work/emdawn/js/library_webgpu_enum_tables.js" \
    "--js-library=$work/emdawn/js/library_webgpu_generated_struct_info.js" \
    "--js-library=$work/emdawn/js/library_webgpu_generated_sig_info.js" \
    "--js-library=$work/emdawn/js/library_webgpu.js" \
    "--pre-js=$script_directory/fallback/pre.js" \
    -sMIN_WEBGL_VERSION=2 \
    -sMAX_WEBGL_VERSION=2 \
    -sGL_ENABLE_GET_PROC_ADDRESS \
    -sSTACK_SIZE=1MB \
    > "$work/linker-flags.txt"

SWIFT_GAME_DAWN_LINKER_FLAGS="$work/linker-flags.txt" \
    SWIFT_GAME_OUTPUT_DIRECTORY="$bin_directory/fallback" \
    "$script_directory/link.sh" swift-game "$configuration"
