#!/bin/sh

# SwiftPM compiles C targets with $CC for both the host (build tools and
# macros) and the target. Send wasm32 compilations to emcc.
for argument in "$@"; do
    case "$argument" in
    wasm32-unknown-emscripten | wasm64-unknown-emscripten)
        exec "${EMCC:-emcc}" "$@"
        ;;
    esac
done

exec "${HOST_CC:-clang}" "$@"
