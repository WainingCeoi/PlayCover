# PlayCover for macOS 27

Run iOS apps and games on Apple Silicon Macs with keyboard, mouse, and controller support. This community fork of [PlayCover](https://github.com/PlayCover/PlayCover) focuses on macOS 27 compatibility, performance, and reliability. App compatibility varies; report problems in [this fork's issue tracker](https://github.com/WainingCeoi/PlayCover/issues).

## Download and install

Download the latest `PlayCover-<version>-macOS27-arm64.dmg` from [GitHub Releases](https://github.com/WainingCeoi/PlayCover/releases/latest). **Xcode and GitHub sign-in are not needed to install a release.** Requires macOS 27 and an Apple Silicon Mac.

1. Quit PlayCover.
2. Open the DMG and drag PlayCover to **Applications**.
3. Choose **Replace** when updating an existing installation, then open PlayCover.

Replacing the app bundle leaves installed games and settings intact. Releases include `SHA256SUMS`, version/build metadata in `BUILD_INFO.txt`, and dependency lockfiles. **Check for Updates** opens this fork's Releases page; updates are installed manually. See the [changelog](CHANGELOG.md) for release changes.

This fork is ad hoc signed and is not notarized. If macOS blocks a build you trust, try opening it once, then use **System Settings → Privacy & Security → Open Anyway**. See [Apple's instructions](https://support.apple.com/102445).

Development builds are available under **Actions → macOS 27 validation → a successful run → Artifacts**. Downloading these artifacts requires GitHub sign-in.

## Manage remote IPA sources

Add and manage catalogs in **PlayCover → Settings → IPA Sources**. To remove a source:

- Right-click its folder under **IPA Library** and choose **Delete Source**.
- Open the source and click the toolbar trash button.
- In **Settings → IPA Sources**, select one or more rows and click **Delete Source** or press Delete.

Removing a source removes its catalog; it does not uninstall its apps. Hover over similarly named sidebar entries to see their source URLs.

## Build from source

Install Xcode 27 and select it with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`. Install build tools with `brew install carthage swiftlint`, then run from the repository directory:

```sh
carthage bootstrap --use-xcframeworks --cache-builds
PLAYCOVER_SKIP_BUILD_SETUP=1 xcodebuild -project PlayCover.xcodeproj -scheme PlayCover -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData \
  -disableAutomaticPackageResolution \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  PLAYCOVER_SIGNING_ENTITLEMENTS=PlayCover/PlayCoverPreview.entitlements \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  PROVISIONING_PROFILE_SPECIFIER= build
bash scripts/package-macos27.sh
```

The disk image is written to `build/download/PlayCover-<version>-macOS27-arm64.dmg`. Packaging verifies signatures and launches the executable in an isolated startup check before creating the DMG. Ad hoc builds use preview entitlements that allow embedded frameworks to load without an Apple Developer Team ID.

Dependency revisions are recorded in `Cartfile.resolved` and `PlayCover.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. Regression checks also run with the macOS 27 Command Line Tools:

```sh
bash scripts/test-macos27.sh
```

See [test instructions](Tests/README.md) for coverage and individual suites.

## Troubleshooting and contributing

For crashes, failed installs, launch errors, or slow operations, [open an issue](https://github.com/WainingCeoi/PlayCover/issues/new/choose) with the PlayCover version/build, macOS 27 version/build, Mac chip, reproduction steps, and any relevant crash log. For app-specific problems, include the app version and App Store link. Remove personal information from logs before posting.

The [upstream user guide](https://playcover.github.io/PlayBook) covers general PlayCover usage. Its downloads and support instructions refer to upstream releases; use this fork's Releases page and issue tracker for this build.

## License and attribution

Distributed under [GPLv3](LICENSE). This fork builds on the work of the [upstream PlayCover contributors](https://github.com/PlayCover/PlayCover/graphs/contributors), originally created by [iVoider](https://github.com/iVoider). Contributor expectations are described in the [Code of Conduct](CODE_OF_CONDUCT.md).

PlayCover uses [PlayTools](https://github.com/PlayCover/PlayTools) and the open source dependencies listed in its [Carthage lockfile](Cartfile.resolved) and [Swift package lockfile](PlayCover.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved). Dependency licenses remain with their respective projects.
