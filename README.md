<div id="top"></div>

‎<h1 align="center">[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![GPLv3 License][license-shield]][license-url]
[![Weblate](https://img.shields.io/weblate/progress/playcover?style=for-the-badge)](https://hosted.weblate.org/projects/playcover/playcover/)
</h1>



<!-- PROJECT LOGO -->
<br />
<div align="center">
  <a href="https://github.com/PlayCover/PlayCover">
    <img src="images/logo.png" alt="Logo" width="80" height="80">
  </a>

  <h3 align="center">PlayCover</h3>

  <p align="center">
    Run iOS apps and games on Apple Silicon Macs with mouse, keyboard and controller support.
    <br />
    <br />
    <a href="https://playcover.github.io/PlayBook">Documentation</a>
    ·
    <a href="https://discord.gg/RNCHsQHr3S">Discord</a>
    ·
    <a href="https://playcover.io/">Website</a>
  </p>
</div>

<!-- ABOUT THE PROJECT -->
## About The Project

Welcome to PlayCover! This software is all about allowing you to run iOS apps and games on Apple Silicon devices. This fork targets macOS 27; older macOS versions are outside its support scope.

PlayCover works by putting applications through a wrapper which imitates an iPad. This allows the apps to run natively and perform very well.

PlayCover also allows you to map custom touch controls to keyboard, which is not possible in alternative sideloading methods such as Sideloadly. 

These controls include all the essentials, from WASD, camera movement, left and right clicks, and individual keymapping, similar to a popular Android emulator’s keymapping system called Bluestacks.

This software was originally designed to run Genshin Impact on your Apple Silicon device, but it can now run a wide range of applications. Unfortunately, not all games are supported, and some may have bugs.

Localisations handled in [Weblate](https://hosted.weblate.org/projects/playcover/).

![Fancy logo](./images/dark.png#gh-dark-mode-only)
![Fancy logo](./images/light.png#gh-light-mode-only)

<p align="right"><a href="#top">⬆️ Back to top️</a></p>

<!-- GETTING STARTED -->
## Getting Started

Follow the instructions below to get Genshin Impact, and many other games, up and running in no time.

### Prerequisites

At the moment, PlayCover can only run on Apple Silicon Macs. This means that only devices with M-series SoCs (eg. M1) are supported.

If you have an Intel Mac, you can explore alternatives like Bootcamp or emulators.

### Downloading this macOS 27 fork

Open this fork's **Actions → macOS 27 validation** workflow and choose a successful run for the branch you want. Download the **PlayCover-macOS27-arm64** artifact at the bottom of the run page (GitHub sign-in is required). Extract the downloaded ZIP, open `PlayCover-macOS27-arm64.dmg`, quit PlayCover, and drag the app to **Applications**. Keep a copy of the previous app if you want to revert. This replaces the app bundle without uninstalling your games.

These preview builds are ad hoc signed and are not notarized. If macOS blocks opening a build you trust, try opening it once, then use **System Settings → Privacy & Security → Open Anyway**. The artifact includes a checksum and the source commit in `BUILD_INFO.txt`.

### Building this macOS 27 fork locally

Install Xcode 27, select it with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`, and install Carthage and SwiftLint (`brew install carthage swiftlint`). From the repository directory:

```sh
carthage update --use-xcframeworks --cache-builds
FASTLANE=1 xcodebuild -project PlayCover.xcodeproj -scheme PlayCover -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  PLAYCOVER_SIGNING_ENTITLEMENTS=PlayCover/PlayCoverPreview.entitlements \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  PROVISIONING_PROFILE_SPECIFIER= build
bash scripts/package-macos27.sh
```

The installable disk image is `build/download/PlayCover-macOS27-arm64.dmg`. Packaging verifies the signatures and launches the executable in an isolated startup-check mode before creating the DMG. Ad hoc builds use a dedicated preview entitlement so macOS can load the bundled Sparkle framework without an Apple Developer Team ID. Normal Developer ID release entitlements are unchanged. Focused regression checks also run with the macOS 27 Command Line Tools: `bash scripts/test-macos27.sh`. See [test instructions](Tests/README.md) for coverage.

### Removing a remote IPA source

Right-click the source folder under **IPA Library** and choose **Delete Source**, or open that source and click the trash button in its toolbar. You can also use **PlayCover → Settings → IPA Sources**: select one or more rows, then click **Delete Source** or press Delete. Removing a source removes its catalog from PlayCover; it does not uninstall apps already installed from it. Hover over similarly named sidebar entries to see their source URLs.

The upstream downloads below do not include unmerged changes from this fork.

### Download

You can download stable releases [here](https://github.com/PlayCover/PlayCover/releases), or build from source by following the instructions in the Documentation.

### Documentation

To learn how to setup and use PlayCover, visit the documentation [here](https://playcover.github.io/PlayBook).

### Homebrew Cask
We host a [Homebrew](https://brew.sh) tap with the [PlayCover cask](https://github.com/PlayCover/homebrew-playcover/blob/master/Casks/playcover-community.rb). To install from it run:

```sh
brew install --cask PlayCover/playcover/playcover-community
```

To uninstall:
1. Remove PlayCover using `brew uninstall --cask playcover-community`;
2. Untap `PlayCover/playcover` with `brew untap PlayCover/playcover`.

<p align="right"><a href="#top">⬆️ Back to top️</a></p>



<!-- LICENSE -->
## License

Distributed under the GPLv3 License. See `LICENSE` for more information.



<!-- CONTACT -->
## Contact

Lucas Lee - playcover@lucas.icu

Depal - depal@playcover.io




<!-- ACKNOWLEDGMENTS -->
## Libraries Used

These open source libraries were used to create this project.

* [inject](https://github.com/paradiseduo/inject)
* [PTFakeTouch](https://github.com/Ret70/PTFakeTouch)
* [DownloadManager](https://github.com/shapedbyiris/download-manager)
* [DataCache](https://github.com/huynguyencong/DataCache)
* [SwiftUI CachedAsyncImage](https://github.com/bullinnyc/CachedAsyncImage)

* Thanks to @iVoider for creating such a great project!

<p align="right"><a href="#top">⬆️ Back to top️</a></p>



<!-- MARKDOWN LINKS & IMAGES -->
[contributors-shield]: https://img.shields.io/github/contributors/PlayCover/PlayCover.svg?style=for-the-badge
[contributors-url]: https://github.com/PlayCover/PlayCover/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/PlayCover/PlayCover.svg?style=for-the-badge
[forks-url]: https://github.com/PlayCover/PlayCover/network/members
[stars-shield]: https://img.shields.io/github/stars/PlayCover/PlayCover.svg?style=for-the-badge
[stars-url]: https://github.com/PlayCover/PlayCover/stargazers
[issues-shield]: https://img.shields.io/github/issues/PlayCover/PlayCover.svg?style=for-the-badge
[issues-url]: https://github.com/PlayCover/PlayCover/issues
[license-shield]: https://img.shields.io/github/license/PlayCover/PlayCover.svg?style=for-the-badge
[license-url]: https://github.com/PlayCover/PlayCover/blob/master/LICENSE
