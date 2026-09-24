#!/bin/bash
set -euo pipefail

app_path="${1:-build/DerivedData/Build/Products/Release/PlayCover.app}"
output_dir="${2:-build/download}"
if [[ ! -d "$app_path" ]]; then
  echo "Build PlayCover.app with Xcode 27 before packaging it: $app_path" >&2
  exit 1
fi

app_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")
if [[ ! "$app_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$build_number" =~ ^[0-9]+$ ]]; then
  echo 'The app must have a three-part numeric version and an integer build number.' >&2
  exit 1
fi
image_name="PlayCover-${app_version}-macOS27-arm64.dmg"

# Preserve the executable permissions, symlinks, and signatures inside the disk image.
/usr/bin/codesign --verify --deep --strict "$app_path"
# Loading the actual executable catches dyld/signing failures that static
# signature verification cannot detect, without initializing app data or UI.
bash "$(dirname "$0")/test-built-app.sh" "$app_path"
mkdir -p "$output_dir"
staging_dir=$(mktemp -d)
trap 'rm -rf "$staging_dir"' EXIT
/usr/bin/ditto "$app_path" "$staging_dir/PlayCover.app"
ln -s /Applications "$staging_dir/Applications"
/usr/bin/hdiutil create -volname "PlayCover ${app_version}" -srcfolder "$staging_dir" \
  -fs HFS+ -format UDZO -ov "$output_dir/$image_name"
/usr/bin/hdiutil verify "$output_dir/$image_name"
(
  cd "$output_dir"
  /usr/bin/shasum -a 256 "$image_name" > SHA256SUMS
)
revision=$(git rev-parse HEAD)
if ! git diff --quiet HEAD --; then
  revision="$revision (uncommitted changes)"
fi
printf 'PlayCover version: %s\nBuild number: %s\nCheckout revision: %s\nTarget: macOS 27, Apple Silicon\nSigning: ad hoc (not notarized)\n' \
  "$app_version" "$build_number" "$revision" > "$output_dir/BUILD_INFO.txt"
cp Cartfile.resolved "$output_dir/Cartfile.resolved"
cp PlayCover.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved \
  "$output_dir/Package.resolved"
