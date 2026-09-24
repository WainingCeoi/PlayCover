#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/playcover-macho-tests.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
xcrun swiftc -target arm64-apple-macosx12.0 -module-cache-path "$build_dir/modules" \
    "$repo_dir/PlayCover/Utils/Extensions/DataExtensions.swift" \
    "$repo_dir/PlayCover/Utils/Macho.swift" \
    "$repo_dir/Tests/Macho/main.swift" \
    -o "$build_dir/macho-tests"
"$build_dir/macho-tests"
