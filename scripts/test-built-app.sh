#!/bin/bash
set -euo pipefail

app_path="${1:-build/DerivedData/Build/Products/Release/PlayCover.app}"
xcrun python3 - "$app_path" <<'PY'
import pathlib
import plistlib
import subprocess
import sys

binary = pathlib.Path(sys.argv[1]).resolve() / "Contents/MacOS/PlayCover"
marker = "PlayCover startup validation passed"
if not binary.is_file():
    sys.exit(f"Built app executable not found: {binary}")

# CI hosts may not enforce library validation as strictly as a user's Mac.
# Check the signed preview's policy too, rather than trusting a successful launch.
signature = subprocess.run(
    ["/usr/bin/codesign", "-dv", "--verbose=4", str(binary)],
    capture_output=True, text=True, check=True,
).stderr
if "Signature=adhoc" in signature:
    signed_entitlements = subprocess.run(
        ["/usr/bin/codesign", "-d", "--entitlements", "-", "--xml", str(binary)],
        capture_output=True, check=True,
    ).stdout
    entitlements = plistlib.loads(signed_entitlements)
    if entitlements.get("com.apple.security.cs.disable-library-validation") is not True:
        sys.exit("Ad hoc preview is missing its library-validation entitlement")
    if entitlements.get("com.apple.security.get-task-allow") is True:
        sys.exit("Distributable preview must not enable debugger access")
    if not any("runtime" in line for line in signature.splitlines() if line.startswith("CodeDirectory ")):
        sys.exit("Ad hoc preview must retain hardened runtime")

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
