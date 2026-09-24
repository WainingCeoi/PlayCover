#!/bin/bash
set -euo pipefail

app_path="${1:-build/DerivedData/Build/Products/Release/PlayCover.app}"
xcrun python3 - "$app_path" <<'PY'
import pathlib
import subprocess
import sys

binary = pathlib.Path(sys.argv[1]).resolve() / "Contents/MacOS/PlayCover"
marker = "PlayCover startup validation passed"
if not binary.is_file():
    sys.exit(f"Built app executable not found: {binary}")

try:
    result = subprocess.run(
        [str(binary), "--validate-startup"],
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )
except subprocess.TimeoutExpired:
    sys.exit("Built app startup validation timed out after 15 seconds")
except OSError as error:
    sys.exit(f"Unable to launch built app: {error}")

if result.returncode != 0 or marker not in result.stdout.splitlines():
    sys.stderr.write(result.stdout)
    sys.stderr.write(result.stderr)
    sys.exit(f"Built app startup validation failed (exit {result.returncode})")

print(marker)
PY
