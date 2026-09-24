//
//  Cacher.swift
//  PlayCover
//
//  Created by Amir Mohammadi on 10/2/1401 AP.
//

import Foundation
import AppKit
import DataCache
import CachedAsyncImage

class Cacher {
    static let shared = Cacher()
    @ImageCache private var imageCache
    let cache = DataCache.instance
    private let localIconLock = NSLock()
    /// We can create a custom cache like this (default values are as the same as below):
    /// `let cache = DataCache(name: "PlayCoverCache")`
    /// `cache.maxDiskCacheSize = 100*1024*1024`      // 100 MB
    /// `cache.maxCachePeriodInSecond = 7*86400`      // 1 week
    /// More details: https://github.com/huynguyencong/DataCache/blob/master/README.md

    init() {
        // Set image cache limit.
        ImageCache().wrappedValue.setCacheLimit(
            countLimit: 400,
            totalCostLimit: 4*1024*1024
        )
    }

    func removeImageCache() {
        imageCache.removeCache()
    }

    func resolveITunesData(_ link: String) async {
        if let refreshedITunesData = await getITunesData(link) {
            try? cache.write(codable: refreshedITunesData, forKey: link)
        }
    }

    func resolveLocalIcon(_ app: PlayApp) -> NSImage? {
        resolveLocalIcon(
            at: app.url,
            bundleIdentifier: app.info.bundleIdentifier,
            bundleVersion: app.info.bundleVersion,
            primaryIconName: app.info.primaryIconName
        )
    }

    func resolveLocalIcon(
        at url: URL,
        bundleIdentifier: String,
        bundleVersion: String,
        primaryIconName: String
    ) -> NSImage? {
        // A version marker plus an unversioned image can return a different version's
        // icon after a downgrade, or an old icon when extracting an update fails.
        let cacheKey = localIconCacheKey(at: url, bundleIdentifier: bundleIdentifier,
                                        bundleVersion: bundleVersion, primaryIconName: primaryIconName)
        localIconLock.lock()
        defer { localIconLock.unlock() }
        guard !Task.isCancelled else { return nil }
        if let cachedImage = cache.readImage(forKey: cacheKey) {
            return cachedImage
        }

        let iconName = primaryIconName.isEmpty ? "AppIcon" : primaryIconName
        var bestImage = bestLooseIcon(at: url, named: iconName)
        guard !Task.isCancelled else { return nil }
        if let assetsExtractor = try? AssetsExtractor(appUrl: url) {
            for icon in assetsExtractor.extractIcons() {
                if bestImage == nil || icon.size.height > (bestImage?.size.height ?? 0) {
                    bestImage = icon
                }
            }
        }
        if let image = bestImage { cache.write(image: image, forKey: cacheKey) }
        return bestImage
    }

    private func bestLooseIcon(at url: URL, named iconName: String) -> NSImage? {
        var bestImage: NSImage?
        if let files = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let file as URL in files {
                guard !Task.isCancelled else { return nil }
                guard file.lastPathComponent.contains(iconName),
                      (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                      let icon = NSImage(contentsOf: file) else { continue }
                if bestImage == nil || icon.size.height > (bestImage?.size.height ?? 0) {
                    bestImage = icon
                }
            }
        }

        return bestImage
    }

    func resolveLocalIconData(
        at url: URL,
        bundleIdentifier: String,
        bundleVersion: String,
        primaryIconName: String
    ) -> Data? {
        resolveLocalIcon(
            at: url,
            bundleIdentifier: bundleIdentifier,
            bundleVersion: bundleVersion,
            primaryIconName: primaryIconName
        )?.tiffRepresentation
    }

    func getLocalIcon(bundleId: String) -> NSImage? {
        if let app = AppsVM.shared.apps.first(where: { $0.info.bundleIdentifier == bundleId }) {
            return cache.readImage(forKey: localIconCacheKey(
                at: app.url, bundleIdentifier: app.info.bundleIdentifier,
                bundleVersion: app.info.bundleVersion, primaryIconName: app.info.primaryIconName))
        } else {
            return nil
        }
    }

    private func localIconCacheKey(at url: URL, bundleIdentifier: String,
                                   bundleVersion: String, primaryIconName: String) -> String {
        let infoURL = url.appendingPathComponent("Info.plist")
        let modified = (try? infoURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970.description ?? ""
        return ["local-icon-v2", url.absoluteString, bundleIdentifier, bundleVersion, primaryIconName, modified]
            .joined(separator: "\u{0}")
    }

}

extension URLCache {
    static let iconCache = URLCache(memoryCapacity: 4*1024*1024, diskCapacity: 20*1024*1024) // 4MB and 20MB
}
