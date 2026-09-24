//
//  AppViewModel.swift
//  PlayCover
//

import Foundation
import Combine

class AppsVM: ObservableObject {

    public static let appDirectory = PlayTools.playCoverContainer.appendingPathComponent("Applications")

    static let shared = AppsVM()

    private struct CachedApp {
        let app: PlayApp
        let infoData: Data
    }

    private static let scanQueue = DispatchQueue(label: "io.playcover.library", qos: .userInitiated)
    private var cachedApps: [URL: CachedApp] = [:]
    private var isFetching = false
    private var needsRefresh = false

    private init() {
        try? AppsVM.ensureBaseDirectoriesExist()
        PlayTools.installOnSystem()
        fetchApps()
    }

    static func ensureBaseDirectoriesExist() throws {
        try FileManager.default.createDirectory(
            at: appDirectory,
            withIntermediateDirectories: true
        )
    }

    @Published var filteredApps: [PlayApp] = []
    @Published var apps: [PlayApp] = []
    @Published var searchText: String = "" {
        didSet { filterApps() }
    }
    @Published var updatingApps = true

    func fetchApps() {
        Task { @MainActor in
            guard !isFetching else {
                needsRefresh = true
                return
            }
            isFetching = true
            updatingApps = true

            let result = await withCheckedContinuation { continuation in
                Self.scanQueue.async {
                    continuation.resume(returning: Result { try Self.loadAppMetadata() })
                }
            }
            switch result {
            case .success(let metadata):
                var loadedApps: [URL: CachedApp] = [:]
                for (url, infoData) in metadata {
                    if let previous = cachedApps[url], previous.infoData == infoData || previous.app.isStarting
                        || previous.app.hasActiveSession {
                        loadedApps[url] = previous
                    } else {
                        // PlayApp prepares settings that use NSScreen; keep object
                        // construction on the main actor, and reuse unchanged apps.
                        loadedApps[url] = CachedApp(app: PlayApp(appUrl: url), infoData: infoData)
                    }
                }
                cachedApps = loadedApps
                apps = loadedApps.values.map(\.app).sorted { $0.name.lowercased() < $1.name.lowercased() }
                filterApps()
            case .failure(let error):
                Log.shared.error(error)
            }
            isFetching = false
            updatingApps = false
            if needsRefresh {
                needsRefresh = false
                fetchApps()
            }
        }
    }

    private func filterApps() {
        let query = searchText.lowercased()
        filteredApps = query.isEmpty ? apps : apps.filter { $0.searchText.contains(query) }
    }

    private static func loadAppMetadata() throws -> [URL: Data] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: appDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        var metadata: [URL: Data] = [:]
        var installedIDs: [String] = []
        for url in contents where url.pathExtension.lowercased() == "app" {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                  let infoData = try? Data(contentsOf: url.appendingPathComponent("Info.plist")) else { continue }
            metadata[url] = infoData
            if let plist = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
               let bundleID = plist["CFBundleIdentifier"] as? String, !bundleID.isEmpty {
                installedIDs.append(bundleID)
            }
        }

        // Preserve IDs of removed apps, used to find their remaining external caches.
        do {
            var bundleIDs = FileManager.default.fileExists(atPath: PlayApp.bundleIDCacheURL.path)
                ? try PlayApp.bundleIDCache : []
            var knownIDs = Set(bundleIDs)
            var cacheChanged = false
            for bundleID in installedIDs where knownIDs.insert(bundleID).inserted {
                bundleIDs.append(bundleID)
                cacheChanged = true
            }
            if cacheChanged {
                try (bundleIDs.joined(separator: "\n") + "\n")
                    .write(to: PlayApp.bundleIDCacheURL, atomically: true, encoding: .utf8)
            }
        } catch {
            Log.shared.error(error)
        }
        return metadata
    }
}
