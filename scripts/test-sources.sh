#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_build="$(mktemp -d "${TMPDIR:-/tmp}/playcover-sources-tests.XXXXXX")"
trap 'rm -rf "$test_build"' EXIT

# Compile the production data declarations without their unrelated SwiftUI views.
# StoreVM itself is compiled unchanged; only networking and paths are isolated.
printf 'import Foundation\n' > "$test_build/SourceTypes.swift"
sed -n '/^struct SourceData:/,/^struct IPASourceSettings:/p' \
    "$repo_root/PlayCover/Views/Settings/IPASourceSettings.swift" | sed '$d' >> "$test_build/SourceTypes.swift"
sed -n '/^enum SourceValidation:/,/^}/p' \
    "$repo_root/PlayCover/Views/Settings/IPASourceSettings.swift" >> "$test_build/SourceTypes.swift"
xcrun swiftc -swift-version 5 -module-cache-path "$test_build/modules" \
    "$repo_root/Tests/Sources/Support.swift" \
    "$test_build/SourceTypes.swift" \
    "$repo_root/PlayCover/ViewModel/StoreVM.swift" \
    "$repo_root/Tests/Sources/SourcesRegression.swift" \
    -o "$test_build/sources-regression"
"$test_build/sources-regression"
