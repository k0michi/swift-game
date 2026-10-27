#!/bin/sh

set -eu

# Checks out Foundation and the packages it builds with at fixed commits, side
# by side as SWIFTCI_USE_LOCAL_DEPS expects, and applies the Emscripten
# patches. SWIFT_GAME_SOURCE_MIRROR names a directory holding clones of these
# repositories (such as a swift checkout made by update-checkout) to fetch
# from instead of GitHub.

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
sources_directory="$repository_root/.build/dependencies/emscripten/foundation"

checkout() {
    name=$1
    url=$2
    commit=$3
    directory="$sources_directory/$name"
    if [ -n "${SWIFT_GAME_SOURCE_MIRROR:-}" ]; then
        url="$SWIFT_GAME_SOURCE_MIRROR/$name"
    fi
    if [ "$(git -C "$directory" rev-parse HEAD 2>/dev/null || true)" = "$commit" ]; then
        return
    fi
    rm -rf "$directory"
    mkdir -p "$directory"
    git -C "$directory" init --quiet
    git -C "$directory" fetch --quiet --depth 1 "$url" "$commit"
    git -C "$directory" checkout --quiet FETCH_HEAD
}

apply_patch() {
    directory="$sources_directory/$1"
    patch=$2
    if git -C "$directory" apply --reverse --check "$patch" 2>/dev/null; then
        return
    fi
    git -C "$directory" apply "$patch"
}

checkout swift-collections https://github.com/apple/swift-collections.git 35a1edcb8ebd2bfe251d587f0b69e62af28f508c
checkout swift-syntax https://github.com/swiftlang/swift-syntax.git 45eb43cda0ccc480c3011219d013f5e710672d8f
checkout swift-foundation-icu https://github.com/swiftlang/swift-foundation-icu.git e8538d259340dd5b8c261f539f2693d094fe2dac
checkout swift-foundation https://github.com/swiftlang/swift-foundation.git ca934a4122014e3f243057869637f108859b9176
checkout swift-corelibs-foundation https://github.com/swiftlang/swift-corelibs-foundation.git 28249ced079d8e7ec03b821c039bf9868738c3fc

apply_patch swift-foundation "$script_directory/swift-foundation.patch"
apply_patch swift-corelibs-foundation "$script_directory/swift-corelibs-foundation.patch"
