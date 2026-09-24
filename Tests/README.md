# macOS 27 regression checks

Run `bash scripts/test-macos27.sh` on an Apple Silicon Mac with macOS 27 and the macOS 27 SDK. Command Line Tools are sufficient for these focused checks. Temporary fixtures and module caches are removed after each suite.

- `test-launch.sh` compiles the production launch, alias, and shell code with test doubles for unrelated services. It signs a disposable flat app bundle and verifies that refreshing an alias binds the final `Info.plist` to its signature. It also checks legacy symlink migration, unchanged-file reuse, late-added bundle entries, stale links, and preservation when the source plist is missing, and launch-state reset after early returns or preparation errors. It does not launch a game or exercise the KeyCover session monitor.
- `test-library.sh` checks library refresh/search behavior, icon metadata fallback, and icon cache/extraction behavior using isolated fixtures and dependency doubles.
- `test-macho.sh` checks malformed Mach-O input, load-command boundaries, universal binary slices, conversion, and safe file replacement using the production parser.

- `test-installation.sh` checks staging and replacement, preserving the installed app on preparation failure, first installation, and exported IPA archive structure/replacement.

The `macOS 27 validation` workflow uses GitHub's `xcode-27` runner and separately builds the full application with ad hoc signing. A complete local build requires Xcode 27, Carthage, SwiftLint, network access for dependencies, and the PlayTools framework. These regressions do not establish compatibility with every iOS app, private framework, game server, or runtime feature.
