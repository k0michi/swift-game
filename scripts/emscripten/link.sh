#!/bin/sh

set -eu

# Links an executable product built by swift-build.sh into HTML, JavaScript and
# wasm. SwiftPM's own link step names the output .wasm, which makes emcc emit
# a standalone module without the JavaScript runtime, and does not link the
# C++ library, so the product is linked here from the objects SwiftPM planned.
#
# Usage: link.sh <product> [configuration]
#
# SWIFT_GAME_DAWN_LINKER_FLAGS can name another file of Dawn's linker flags,
# and SWIFT_GAME_OUTPUT_DIRECTORY another directory for the output, as
# link-webgl2.sh does.

. "$(dirname -- "$0")/env.sh"

product=$1
configuration=${2:-debug}
bin_directory=$(swift_build --configuration "$configuration" --show-bin-path)
dawn_linker_flags=${SWIFT_GAME_DAWN_LINKER_FLAGS:-"$repository_root/.build/dependencies/emscripten/dawn/linker-flags.txt"}
output_directory=${SWIFT_GAME_OUTPUT_DIRECTORY:-$bin_directory}
objects="$bin_directory/$product.objects"

# The objects are the inputs of SwiftPM's link command in its llbuild manifest.
python3 - "$repository_root/.build/$configuration.yaml" "$product" "$objects" <<'EOF'
import json, os, re, sys
manifest, product, objects = sys.argv[1:]
node = re.escape(f'C.{product}-wasm32-unknown-emscripten-') + r'[a-z]+' + re.escape('.exe')
match = re.search(rf'^  "{node}":\n    tool: shell\n    inputs: (\[.*\])$', open(manifest).read(), re.M)
if not match:
    sys.exit(f'No link command for {product} in {manifest}')
# The module wrapper objects for debug info are planned but not always made.
inputs = [i for i in json.loads(match.group(1)) if i.endswith(('.o', '.a'))
          and not (i.endswith('.swiftmodule.o') and not os.path.exists(i))]
missing = [i for i in inputs if not os.path.exists(i)]
if missing:
    sys.exit('Missing objects:\n' + '\n'.join(missing))
quote = lambda path: "'" + path.replace("'", "'\\''") + "'\n"
with open(objects, 'w') as file:
    file.writelines(quote(i) for i in inputs)
EOF

# Library paths and -l flags go to swiftc; everything else is for emcc.
set --
for flags in "$repository_root/.build/dependencies/emscripten/sdl3/linker-flags.txt" \
    "$dawn_linker_flags" \
    "$repository_root/.build/dependencies/emscripten/stb/stb_image-linker-flags.txt" \
    "$repository_root/.build/dependencies/emscripten/stb/stb_image_write-linker-flags.txt" \
    "$repository_root/.build/dependencies/emscripten/stb/stb_vorbis-linker-flags.txt" \
    "$repository_root/.build/dependencies/emscripten/stb/stb_rect_pack-linker-flags.txt" \
    "$repository_root/.build/dependencies/emscripten/stb/stb_truetype-linker-flags.txt"; do
    while IFS= read -r flag; do
        case "$flag" in
        "") ;;
        -l* | /*) set -- "$@" "$flag" ;;
        *) set -- "$@" -Xlinker-driver "$flag" ;;
        esac
    done < "$flags"
done

sdk_root=$(swift_sdk_path sdkRootPath)
resource_directory=$(swift_sdk_path swiftStaticResourcesPath)
tools_directory="$(dirname -- "$sdk_root")/swift.xctoolchain/usr/bin"

"${SWIFT_EXEC:-swiftc}" \
    -o "$output_directory/$product.html" \
    -module-name "$(echo "$product" | tr -- '-' '_')" \
    -emit-executable \
    -target wasm32-unknown-emscripten \
    -static-stdlib \
    -sdk "$sdk_root" \
    -resource-dir "$resource_directory" \
    -tools-directory "$tools_directory" \
    -L "$bin_directory" \
    "@$objects" \
    -Xlinker-driver -sDEFAULT_TO_CXX=1 \
    -Xlinker-driver -sALLOW_MEMORY_GROWTH=1 \
    "$@"

echo "Linked $output_directory/$product.html"
