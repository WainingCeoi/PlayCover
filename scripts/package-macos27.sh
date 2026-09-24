#!/bin/bash
set -euo pipefail

app_path="${1:-build/DerivedData/Build/Products/Release/PlayCover.app}"
output_dir="${2:-build/download}"
if [[ ! -d "$app_path" ]]; then
  echo "Build PlayCover.app with Xcode 27 before packaging it: $app_path" >&2
  exit 1
fi

# Preserve the executable permissions, symlinks, and signatures inside the disk image.
/usr/bin/codesign --verify --deep --strict "$app_path"
mkdir -p "$output_dir"
staging_dir=$(mktemp -d)
trap 'rm -rf "$staging_dir"' EXIT
/usr/bin/ditto "$app_path" "$staging_dir/PlayCover.app"
ln -s /Applications "$staging_dir/Applications"
/usr/bin/hdiutil create -volname 'PlayCover macOS 27' -srcfolder "$staging_dir" \
  -fs HFS+ -format UDZO -ov "$output_dir/PlayCover-macOS27-arm64.dmg"
/usr/bin/hdiutil verify "$output_dir/PlayCover-macOS27-arm64.dmg"
(
  cd "$output_dir"
  /usr/bin/shasum -a 256 PlayCover-macOS27-arm64.dmg > SHA256SUMS
)
revision=$(git rev-parse HEAD)
if ! git diff --quiet HEAD --; then
  revision="$revision (uncommitted changes)"
fi
printf 'Checkout revision: %s\nTarget: macOS 27, Apple Silicon\nSigning: ad hoc (not notarized)\n' \
  "$revision" > "$output_dir/BUILD_INFO.txt"
