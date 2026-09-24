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

verify_hardened_signature() {
    /usr/bin/codesign --verify --strict "$test_dir/Preview Loader"
    /usr/bin/codesign -d --verbose=4 "$test_dir/Preview Loader" \
        2> "$test_dir/signature.log"
    if ! /usr/bin/grep -Eq '^CodeDirectory .*flags=.*[(,]runtime[),]' "$test_dir/signature.log" || \
        ! /usr/bin/grep -q '^Signature=adhoc$' "$test_dir/signature.log"; then
        cat "$test_dir/signature.log"
        printf 'Expected an ad hoc signature with hardened runtime enabled.\n' >&2
        exit 1
    fi
}

verify_hardened_signature

# Both files have valid ad hoc signatures, but no Team ID. Hosts enforcing
# library validation reject the library until the preview exception is applied.
failure_status=0
"$test_dir/Preview Loader" "$test_dir/Preview Library.dylib" \
    > "$test_dir/without-exception.log" 2>&1 || failure_status=$?
if [[ "$failure_status" == 0 ]]; then
    printf 'SKIP negative control: this host does not enforce library validation for the ad hoc fixture.\n'
    printf 'The signed entitlement, hardened runtime, and successful framework call remain required.\n'
elif [[ "$failure_status" == 10 ]] && \
    /usr/bin/grep -Eq 'different Team IDs|no Team ID' "$test_dir/without-exception.log"; then
    printf 'Confirmed rejection without preview entitlement:\n'
    cat "$test_dir/without-exception.log"
else
    cat "$test_dir/without-exception.log"
    printf 'Unexpected negative-control failure; exit status was %s.\n' \
        "$failure_status" >&2
    exit 1
fi

# Use the same entitlement file as the downloadable preview build.
/usr/bin/codesign --force --sign - --options runtime --timestamp=none \
    --entitlements "$repo_dir/PlayCover/PlayCoverPreview.entitlements" \
    "$test_dir/Preview Loader"
verify_hardened_signature
/usr/bin/codesign -d --entitlements - --xml "$test_dir/Preview Loader" \
    > "$test_dir/signed-entitlements.plist"
preview_exception="$(/usr/bin/plutil \
    -extract 'com\.apple\.security\.cs\.disable-library-validation' raw -expect bool \
    "$test_dir/signed-entitlements.plist")"
if [[ "$preview_exception" != true ]]; then
    printf 'The signed preview must include the library-validation exception as Boolean true.\n' >&2
    exit 1
fi
"$test_dir/Preview Loader" "$test_dir/Preview Library.dylib"
printf 'Preview signing regression passed.\n'
