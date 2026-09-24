import AppKit
import Foundation

@main
struct LibraryRegression {
    @MainActor
    static func main() async throws {
        defer { try? FileManager.default.removeItem(at: PlayTools.playCoverContainer) }
        let applications = PlayTools.playCoverContainer.appendingPathComponent("Applications")
        let alpha = try makeApp(in: applications, name: "Alpha", identifier: "test.alpha")
        let beta = try makeApp(in: applications, name: "Beta", identifier: "test.beta")
        _ = try makeApp(in: applications, name: "Ignored", identifier: "test.ignored", extension: "appbackup")
        try "test.removed\n".write(to: PlayApp.bundleIDCacheURL, atomically: true, encoding: .utf8)

        let library = AppsVM.shared
        try await waitUntil { !library.updatingApps && library.apps.count == 2 }
        precondition(PlayApp.initializedOnMainThread, "App settings construction uses AppKit and must stay on main")
        precondition(library.apps.map(\.name) == ["Alpha", "Beta"], "Only exact .app bundles should be loaded")
        let initialCount = PlayApp.initializationCount
        let alphaApp = library.apps[0]
        checkSearch(in: library)

        // A burst of refresh requests should serialize and retain unchanged objects.
        for _ in 0..<20 { library.fetchApps() }
        try await Task.sleep(nanoseconds: 200_000_000)
        try await waitUntil { !library.updatingApps }
        precondition(PlayApp.initializationCount == initialCount)
        precondition(library.apps[0] === alphaApp, "Refresh must preserve launch state on unchanged apps")
        let cachedIDs = try PlayApp.bundleIDCache
        precondition(Set(cachedIDs) == Set(["test.removed", "test.alpha", "test.beta"]))

        // Signing can rewrite Info.plist while a game is open. Its monitor and
        // sleep/keychain state must retain the same owning PlayApp until it exits.
        alphaApp.hasActiveSession = true
        _ = try makeApp(in: applications, name: "Alpha", identifier: "test.alpha", displayName: "Updated")
        library.fetchApps()
        try await Task.sleep(nanoseconds: 100_000_000)
        try await waitUntil { !library.updatingApps }
        precondition(library.apps[0] === alphaApp)
        precondition(PlayApp.initializationCount == initialCount)
        alphaApp.hasActiveSession = false

        // A replacement at the same URL must acquire new metadata, including the
        // search text entered while its asynchronous scan is in progress.
        library.fetchApps()
        library.searchText = "UPDATED"
        try await waitUntil { library.filteredApps.first?.name == "Updated" && !library.updatingApps }
        precondition(library.filteredApps[0] !== alphaApp)
        precondition(PlayApp.initializationCount == initialCount + 1)
        try FileManager.default.removeItem(at: beta)
        library.fetchApps()
        try await waitUntil { library.apps.count == 1 && !library.updatingApps }
        let historicalIDs = try PlayApp.bundleIDCache
        precondition(historicalIDs.contains("test.beta"), "Removed IDs are needed for external cache cleanup")

        try checkIconMetadata(at: alpha)
        try checkIconCache(at: alpha)
        try Data().write(to: alpha.appendingPathComponent("Assets.car"))
        CUICatalog.requestedNames = []
        _ = try AssetsExtractor(appUrl: alpha).extractIcons()
        precondition(CUICatalog.requestedNames == ["AppIcon60x60"], "Unrelated renditions must never be loaded")
        print("PASS: library filtering, background refresh, identity retention, metadata replacement, cache history,")
        print("      empty icon metadata, versioned icon caching, deferred cache writes, and selective asset loading")
    }

    @MainActor
    private static func checkSearch(in library: AppsVM) {
        let initialCount = PlayApp.initializationCount
        let alphaApp = library.apps[0]
        library.searchText = "aLP"
        precondition(library.filteredApps.count == 1 && library.filteredApps[0] === alphaApp)
        library.searchText = "missing"
        precondition(library.filteredApps.isEmpty)
        library.searchText = ""
        precondition(library.filteredApps.count == 2)
        precondition(PlayApp.initializationCount == initialCount, "Typing must not reconstruct apps or their aliases")
    }

    @MainActor
    private static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        preconditionFailure("Timed out waiting for library update")
    }

    private static func makeApp(in directory: URL, name: String, identifier: String,
                                extension fileExtension: String = "app", displayName: String? = nil) throws -> URL {
        let url = directory.appendingPathComponent(name).appendingPathExtension(fileExtension)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let metadata = ["CFBundleIdentifier": identifier, "CFBundleName": displayName ?? name,
                        "CFBundleShortVersionString": "1.0"]
        try PropertyListSerialization.data(fromPropertyList: metadata, format: .binary, options: 0)
            .write(to: url.appendingPathComponent("Info.plist"))
        return url
    }

    private static func checkIconMetadata(at url: URL) throws {
        let info = AppInfo(contentsOf: url.appendingPathComponent("Info.plist"))
        info[strings: "CFBundleIconFiles"] = []
        info[dictionary: "CFBundleIcons~ipad"] = ["CFBundlePrimaryIcon": ["CFBundleIconFiles": []]]
        info[dictionary: "CFBundleIcons"] = ["CFBundlePrimaryIcon": ["CFBundleIconFiles": []]]
        precondition(info.primaryIconName == "AppIcon", "Empty icon arrays must not crash")
        info[strings: "CFBundleIconFiles"] = ["LegacyIcon", ""]
        precondition(info.primaryIconName == "LegacyIcon", "Empty platform-specific lists must fall through")
        info[dictionary: "CFBundleIcons"] = ["CFBundlePrimaryIcon": ["CFBundleIconFiles": ["PhoneIcon"]]]
        precondition(info.primaryIconName == "PhoneIcon")
        info[dictionary: "CFBundleIcons~ipad"] = ["CFBundlePrimaryIcon": ["CFBundleIconFiles": ["TabletIcon"]]]
        precondition(info.primaryIconName == "TabletIcon")
    }

    private static func checkIconCache(at url: URL) throws {
        let iconURL = url.appendingPathComponent("AppIcon.png")
        try writeIcon(at: iconURL, size: 16)
        let cacher = Cacher()
        func resolve(_ version: String) -> NSImage? {
            cacher.resolveLocalIcon(at: url, bundleIdentifier: "test.alpha", bundleVersion: version,
                                    primaryIconName: "AppIcon")
        }
        precondition(resolve("1")?.size.width == 16)
        try writeIcon(at: iconURL, size: 32)
        precondition(resolve("2")?.size.width == 32)
        precondition(resolve("1")?.size.width == 16, "Downgrading must not reuse the newer version's icon")
        try writeIcon(at: iconURL, size: 40)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 123_456)],
                                              ofItemAtPath: url.appendingPathComponent("Info.plist").path)
        precondition(resolve("2")?.size.width == 40, "A replaced build can retain the same marketing version")
        try FileManager.default.removeItem(at: iconURL)
        precondition(resolve("3") == nil, "Failed extraction must not return the previous version's icon")
        try writeIcon(at: iconURL, size: 24)
        DataCache.instance.deferWrites = true
        defer { DataCache.instance.deferWrites = false }
        precondition(resolve("4")?.size.width == 24, "Return the extracted image before cache persistence finishes")
    }

    private static func writeIcon(at url: URL, size: Int) throws {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            preconditionFailure("Could not make fixture icon")
        }
        try data.write(to: url)
    }
}
