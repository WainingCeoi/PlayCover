#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
os_version=$(sw_vers -productVersion)
sdk_version=$(xcrun --sdk macosx --show-sdk-version)
if [[ "${os_version%%.*}" != 27 || "${sdk_version%%.*}" != 27 ]]; then
  echo "These regressions require macOS 27 and the macOS 27 SDK (found OS $os_version, SDK $sdk_version)." >&2
  exit 1
fi
bash scripts/test-launch.sh
bash scripts/test-library.sh
bash scripts/test-macho.sh
bash scripts/test-installation.sh
