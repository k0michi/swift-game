#!/bin/sh

set -eu

# Builds Tests/EchoBrowserTests and Tests/FetchBrowserTests for the browser
# and runs them in headless Chromium with Playwright.

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
tests_directory="$repository_root/Tests/EchoBrowserTests"

"$script_directory/build-sdl.sh"
"$script_directory/build-dawn.sh"
"$script_directory/swift-build.sh" --target EchoBrowserTests
"$script_directory/link.sh" EchoBrowserTests
"$script_directory/swift-build.sh" --target FetchBrowserTests
"$script_directory/link.sh" FetchBrowserTests

if [ ! -d "$tests_directory/node_modules" ]; then
    npm ci --prefix "$tests_directory" --no-audit --no-fund
    npx --prefix "$tests_directory" playwright install chromium
fi

node "$tests_directory/runner.js" "$repository_root/.build/wasm32-unknown-emscripten/debug" EchoBrowserTests.html
node "$tests_directory/runner.js" "$repository_root/.build/wasm32-unknown-emscripten/debug" FetchBrowserTests.html
