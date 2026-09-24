#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
export CLANG_MODULE_CACHE_PATH="$test_dir/module-cache"
printf 'int main(void) { return 0; }\n' > "$test_dir/fixture.c"
xcrun clang "$test_dir/fixture.c" -o "$test_dir/fixture"
xcrun swiftc -target arm64-apple-macosx12.0 -swift-version 5 -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  Tests/Launch/Support.swift \
  PlayCover/Model/BaseApp.swift PlayCover/Model/AppInfo.swift PlayCover/Model/PlayApp.swift \
  PlayCover/PlayCoverError.swift PlayCover/Utils/Shell.swift \
  PlayCover/Utils/Extensions/URLExtensions.swift PlayCover/Utils/Extensions/FileExtensions.swift \
  PlayCover/Utils/Extensions/PlayAppExtensions.swift Tests/Launch/main.swift \
  -o "$test_dir/launch-regressions"
"$test_dir/launch-regressions" "$test_dir/fixture"
