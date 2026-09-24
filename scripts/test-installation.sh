#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/playcover-installer-tests.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
xcrun swiftc -target arm64-apple-macosx27.0 -module-cache-path "$build_dir/modules" \
    "$repo_dir/PlayCover/AppInstaller/InstallationTransaction.swift" \
    "$repo_dir/PlayCover/AppInstaller/IPAArchive.swift" \
    "$repo_dir/Tests/Installer/main.swift" \
    -o "$build_dir/installer-tests"
"$build_dir/installer-tests"
