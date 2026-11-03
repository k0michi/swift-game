#!/bin/sh

set -eu

# Copies the release builds of the games, which build.sh -c release makes,
# into the directory given, with what they need beside them. SDL and Dawn are
# linked statically, so macOS has all the games need, and Linux gets the
# toolchain's Swift runtime in lib, found through the executable's run path.
#
# Usage: package.sh <directory>

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
package=$1
bin_path=$(swift build --package-path "$repository_root" -c release --show-bin-path | tail -n 1)
toolchain=$(CDPATH= cd -- "$(dirname -- "$(command -v swiftc)")/../.." && pwd)

mkdir -p "$package"
cp "$bin_path/NotoSansJP-Regular.otf" "$bin_path/NotoSansJP-LICENSE.txt" "$package/"
for game in swift-game shooter pong text; do
    cp "$bin_path/$game" "$package/"
    if [ "$(uname -s)" = Linux ]; then
        mkdir -p "$package/lib"
        ldd "$package/$game" |
            awk -v toolchain="$toolchain/" 'index($3, toolchain) == 1 { print $3 }' |
            xargs -r cp -t "$package/lib"
        patchelf --set-rpath '$ORIGIN/lib' "$package/$game"
    fi
done
