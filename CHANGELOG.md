# Changelog

## 3.1.1 — 2026-09-24

First release of the WainingCeoi macOS 27 fork, build 857. Requires macOS 27 and an Apple Silicon Mac.

- Refresh launch aliases after app preparation and signing to address the permission-to-open “(null)” failure. Propagate launch errors and clear failed launch state.
- Keep library searches responsive by filtering loaded apps and coalescing metadata scans off the main thread. Preserve active app instances and avoid stale icon caches.
- Stage and sign installations before replacing existing apps. Preserve installed apps when preparation fails, report failures accurately, and create fresh IPA exports.
- Validate Mach-O boundaries and universal binary slices before conversion and preserve executable permissions during replacement.
- Remove remote IPA sources from the sidebar context menu, source toolbar, or Settings. Clear stale catalogs even when offline and reject late responses from removed sources.
- Fix the ad hoc framework-signing configuration that could stop PlayCover itself from opening. Packaging now checks signed entitlements and runs the real executable before creating a DMG.
- Route update checks to this fork's GitHub Releases page and pin the runtime/dependency revisions used for the release.

The app is ad hoc signed and is not notarized. Updates are installed manually. Game compatibility still varies; this release does not claim to resolve every game-specific runtime issue.
