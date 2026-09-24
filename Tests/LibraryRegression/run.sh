#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
test_build="$(mktemp -d "${TMPDIR:-/tmp}/playcover-library-tests.XXXXXX")"
trap 'rm -rf "$test_build"' EXIT

# Substitute only the two external cache imports. All production library, plist,
# icon selection and asset filtering implementations are compiled unchanged.
sed -e '/^import DataCache$/d' -e '/^import CachedAsyncImage$/d' \
    "$repo_root/PlayCover/Utils/Cacher.swift" > "$test_build/Cacher.swift"
xcrun swiftc -swift-version 5 -module-cache-path "$test_build/modules" \
    "$repo_root/Tests/LibraryRegression/TestSupport.swift" \
    "$repo_root/Tests/LibraryRegression/LibraryRegression.swift" \
    "$repo_root/PlayCover/ViewModel/AppsVM.swift" \
    "$repo_root/PlayCover/Model/AppInfo.swift" \
    "$repo_root/PlayCover/Utils/AssetsExtractor.swift" \
    "$test_build/Cacher.swift" \
    -o "$test_build/library-regression"
"$test_build/library-regression"
