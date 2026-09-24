import Foundation

@main
struct SourcesRegression {
    @MainActor
    static func main() async throws {
        try FileManager.default.createDirectory(at: PlayTools.playCoverContainer, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: PlayTools.playCoverContainer) }
        try await checkIdentityAndOfflineDeletion()
        try await checkDeletionDuringRequest()
        try await checkSupersededRefresh()
        print("PASS: configured source identity, duplicate remote IDs, enabled-app deduplication, persistent removal,")
        print("      last-source/offline removal, same-count replacement, and stale in-flight refresh rejection")
    }

    @MainActor
    private static func checkIdentityAndOfflineDeletion() async throws {
        let first = SourceData(source: "https://example.com/first.json", isEnabled: true)
        let second = SourceData(source: "https://example.com/second.json", isEnabled: true)
        let requests = SourceRequests()
        let connection = TestConnection()
        let store = try makeStore("identity", sources: [first, second], requests: requests, connection: connection)
        let remoteID = UUID()
        let sharedApp = app("shared")
        try await waitUntil { await requests.count == 1 }
        await requests.respond(with: try payload([sharedApp, app("first")], id: remoteID))
        try await waitUntil { await requests.count == 1 }
        await requests.respond(with: try payload([sharedApp, app("second")], id: remoteID))
        await store.awaitResolveSources()
        precondition(store.sourcesData.map(\.id) == [first.id, second.id], "Remote IDs must use local identities")
        precondition(store.sourcesApps.map(\.bundleID) == ["shared", "first", "second"])

        // The SourceData captured by a row may still have the old checking status.
        store.enableSourceToggle(source: first, value: false)
        precondition(store.sourcesApps.map(\.bundleID) == ["shared", "second"])
        store.enableSourceToggle(source: first, value: true)
        connection.isConnected = false
        store.removeSources(ids: [first.id])
        precondition(store.sourcesList.map(\.id) == [second.id])
        precondition(store.sourcesData.map(\.id) == [second.id])
        precondition(store.sourcesApps.map(\.bundleID) == ["shared", "second"])
        let saved = try readSources("identity")
        precondition(saved.map(\.id) == [second.id], "Removal must persist without network access")

        var selection: Set<UUID> = [second.id]
        store.deleteSource(&selection)
        precondition(selection.isEmpty)
        precondition(store.sourcesList.isEmpty && store.sourcesData.isEmpty && store.sourcesApps.isEmpty)
        let reloaded = StoreVM(plistSource: plist("identity"), isConnected: { false })
        precondition(reloaded.sourcesList.isEmpty, "Deleted sources must stay deleted after restarting")
        let outstanding = await requests.count
        precondition(outstanding == 0, "Offline deletion must not start network requests")
    }

    @MainActor
    private static func checkDeletionDuringRequest() async throws {
        let removed = SourceData(source: "https://example.com/removed.json", isEnabled: true)
        let replacement = SourceData(source: "https://example.com/replacement.json", isEnabled: true)
        let requests = SourceRequests()
        let connection = TestConnection()
        let store = try makeStore("inflight", sources: [removed], requests: requests, connection: connection)
        try await waitUntil { await requests.count == 1 }
        var awaitingOriginal = false
        let original = Task { @MainActor in
            awaitingOriginal = true
            await store.awaitResolveSources()
        }
        try await waitUntil { awaitingOriginal }
        store.removeSources(ids: [removed.id])
        precondition(store.sourcesList.isEmpty && store.sourcesData.isEmpty && store.sourcesApps.isEmpty)
        store.addSource(replacement)
        try await waitUntil { await requests.count == 2 }
        // Replace the source before the previous response arrives, preserving the
        // list count that the old resolver used as its only validity check.
        await requests.respond(with: try payload([app("removed")], id: removed.id))
        await original.value
        precondition(store.sourcesData.isEmpty, "An old response must not resurrect a removed source")
        precondition(store.sourcesList[0].status == .checking, "An old response must not update its replacement")
        await requests.respond(with: try JSONEncoder().encode([app("replacement")]))
        await store.awaitResolveSources()
        precondition(store.sourcesData.map(\.id) == [replacement.id], "Legacy JSON also uses configured identity")
        precondition(store.sourcesApps.map(\.bundleID) == ["replacement"])
        store.removeSources(ids: [replacement.id])
        precondition(store.sourcesList.isEmpty && store.sourcesData.isEmpty && store.sourcesApps.isEmpty)
        let saved = try readSources("inflight")
        precondition(saved.isEmpty)
    }

    @MainActor
    private static func checkSupersededRefresh() async throws {
        let source = SourceData(source: "https://example.com/refresh.json", isEnabled: true)
        let requests = SourceRequests()
        let store = try makeStore("refresh", sources: [source], requests: requests, connection: TestConnection())
        try await waitUntil { await requests.count == 1 }
        var awaitingOriginal = false
        let original = Task { @MainActor in
            awaitingOriginal = true
            await store.awaitResolveSources()
        }
        try await waitUntil { awaitingOriginal }
        store.resolveSources()
        try await waitUntil { await requests.count == 2 }
        await requests.respond(with: try payload([app("new")], id: UUID()), at: 1)
        await store.awaitResolveSources()
        await requests.respond(with: try payload([app("old")], id: UUID()))
        await original.value
        precondition(store.sourcesData.count == 1, "Superseded refresh must not duplicate a source")
        precondition(store.sourcesApps.map(\.bundleID) == ["new"], "Late responses must not replace fresher data")
    }

    @MainActor
    private static func makeStore(_ name: String, sources: [SourceData], requests: SourceRequests,
                                  connection: TestConnection) throws -> StoreVM {
        try PropertyListEncoder().encode(sources).write(to: plist(name))
        return StoreVM(plistSource: plist(name), loadData: { try await requests.load($0) },
                       isConnected: { connection.isConnected })
    }

    private static func plist(_ name: String) -> URL {
        PlayTools.playCoverContainer.appendingPathComponent(name).appendingPathExtension("plist")
    }

    private static func readSources(_ name: String) throws -> [SourceData] {
        try PropertyListDecoder().decode([SourceData].self, from: Data(contentsOf: plist(name)))
    }

    private static func app(_ identifier: String) -> SourceAppsData {
        SourceAppsData(bundleID: identifier, name: identifier, version: "1", itunesLookup: "",
                       link: "https://example.com/\(identifier).ipa", checksum: nil)
    }

    private static func payload(_ apps: [SourceAppsData], id: UUID) throws -> Data {
        try JSONEncoder().encode(SourceJSON(name: "www.maclub.net", data: apps, id: id))
    }

    @MainActor
    private static func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<300 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        preconditionFailure("Timed out waiting for a source request")
    }
}
