# macOS 27 regression checks

Run `bash scripts/test-macos27.sh` on an Apple Silicon Mac with macOS 27 and the macOS 27 SDK. Command Line Tools are sufficient for these focused checks. Temporary fixtures and module caches are removed after each suite. The launch, Mach-O, and installation harnesses compile against the macOS 12 deployment target. Runtime validation is performed on macOS 27; it does not establish runtime compatibility with older macOS versions.

- `test-launch.sh` compiles the production launch, alias, and shell code with test doubles for unrelated services. It signs a disposable flat app bundle and verifies that refreshing an alias binds the final `Info.plist` to its signature. It also checks legacy symlink migration, unchanged-file reuse, late-added bundle entries, stale links, and preservation when the source plist is missing, and launch-state reset after early returns or preparation errors. It does not launch a game or exercise the KeyCover session monitor.
- `test-library.sh` checks library refresh/search behavior, icon metadata fallback, and icon cache/extraction behavior using isolated fixtures and dependency doubles.
- `test-macho.sh` checks malformed Mach-O input, load-command boundaries, universal binary slices, conversion, and safe file replacement using the production parser.

- `test-installation.sh` checks staging and replacement, preserving the installed app on preparation failure, first installation, and exported IPA archive structure/replacement.
- `test-sources.sh` checks source removal, persistence, duplicate catalog identities, and cancelled refreshes using isolated catalog fixtures.
- `test-preview-signing.sh` checks that the production preview entitlements allow an ad hoc signed process to load its embedded library with hardened runtime enabled. The negative control reproduces the rejection on Macs enforcing library validation; hosts that allow it report that limitation and still run the signed-entitlement and successful-load checks.

After a full build, `bash scripts/test-built-app.sh /path/to/PlayCover.app` verifies the actual signed preview entitlements and hardened runtime, then runs the real executable with `--validate-startup` and a timeout. This mode exits before initializing PlayCover's app state, user data, network requests, or UI. It detects loader and framework-signing failures; it does not test windows or game launches. DMG packaging requires this check to pass.

The `macOS 27 validation` workflow uses GitHub's `xcode-27` runner and separately builds the full application with ad hoc signing. A complete local build requires Xcode 27, Carthage, SwiftLint, network access for dependencies, and the PlayTools framework. These regressions do not establish compatibility with every iOS app, private framework, game server, or runtime feature.

To reproduce the workflow's ad hoc build locally with Xcode 27:

```sh
carthage bootstrap --use-xcframeworks --cache-builds
FASTLANE=1 xcodebuild -project PlayCover.xcodeproj -scheme PlayCover -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData \
  -disableAutomaticPackageResolution \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  PLAYCOVER_SIGNING_ENTITLEMENTS=PlayCover/PlayCoverPreview.entitlements \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO PROVISIONING_PROFILE_SPECIFIER= build
bash scripts/package-macos27.sh
```

The preview entitlement override applies only to the PlayCover target. Normal release signing keeps the existing release entitlements, signing configuration, and Sparkle updater. The workflow's dependency revisions are recorded in `Cartfile.resolved` and the project workspace's `Package.resolved`; packaging includes copies alongside the DMG and its checksum.
