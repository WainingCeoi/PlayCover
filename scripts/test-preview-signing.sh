#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/playcover preview-signing.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

cat > "$test_dir/library.c" <<'EOF'
int preview_signing_value(void) {
    return 27;
}
EOF

cat > "$test_dir/loader.c" <<'EOF'
#include <dlfcn.h>
#include <stdio.h>

int main(int argc, char **argv) {
    if (argc != 2) {
        return 2;
    }
    void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (library == NULL) {
        fprintf(stderr, "%s\n", dlerror());
        return 10;
    }
    int (*value)(void) = (int (*)(void))dlsym(library, "preview_signing_value");
    if (value == NULL || value() != 27) {
        dlclose(library);
        return 11;
    }
    dlclose(library);
    puts("Preview framework loaded successfully.");
    return 0;
}
EOF

xcrun clang -target arm64-apple-macosx27.0 -dynamiclib \
    "$test_dir/library.c" -o "$test_dir/Preview Library.dylib"
xcrun clang -target arm64-apple-macosx27.0 \
    "$test_dir/loader.c" -o "$test_dir/Preview Loader"

/usr/bin/codesign --force --sign - --options runtime --timestamp=none \
    "$test_dir/Preview Library.dylib"
/usr/bin/codesign --force --sign - --options runtime --timestamp=none \
    "$test_dir/Preview Loader"

# Both files have valid ad hoc signatures, but no Team ID. Hardened runtime
# must reject the library until the preview-only exception is applied.
failure_status=0
"$test_dir/Preview Loader" "$test_dir/Preview Library.dylib" \
    > "$test_dir/without-exception.log" 2>&1 || failure_status=$?
if [[ "$failure_status" != 10 ]] || \
    ! /usr/bin/grep -Eq 'different Team IDs|no Team ID' "$test_dir/without-exception.log"; then
    cat "$test_dir/without-exception.log"
    printf 'Expected library validation to reject an ad hoc framework; exit status was %s.\n' \
        "$failure_status" >&2
    exit 1
fi
printf 'Confirmed rejection without preview entitlement:\n'
cat "$test_dir/without-exception.log"

# Use the same entitlement file as the downloadable preview build.
/usr/bin/codesign --force --sign - --options runtime --timestamp=none \
    --entitlements "$repo_dir/PlayCover/PlayCoverPreview.entitlements" \
    "$test_dir/Preview Loader"
/usr/bin/codesign --verify --strict "$test_dir/Preview Loader"
"$test_dir/Preview Loader" "$test_dir/Preview Library.dylib"
printf 'Preview signing regression passed.\n'
