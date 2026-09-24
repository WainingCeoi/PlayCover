//
//  Store.swift
//  PlayCover
//
//  Created by Isaac Marovitz on 06/08/2022.
//

import Foundation
import Combine

class StoreVM: ObservableObject, @unchecked Sendable {
    public static let shared = StoreVM()
    private let plistSource: URL
    private let loadData: (URLRequest) async throws -> (Data, URLResponse)
    private let isConnected: () -> Bool

    private convenience init() {
        self.init(plistSource: PlayTools.playCoverContainer
            .appendingPathComponent("Sources")
            .appendingPathExtension("plist"))
    }

    init(plistSource: URL,
         loadData: @escaping (URLRequest) async throws -> (Data, URLResponse) = {
             try await URLSession.shared.data(for: $0)
         },
         isConnected: @escaping () -> Bool = NetworkVM.isConnectedToNetwork) {
        self.plistSource = plistSource
        self.loadData = loadData
        self.isConnected = isConnected
        sourcesList = []
        if !decode() { encode() }
        resolveSources()
    }

    @Published var sourcesList: [SourceData] {
        didSet {
            encode()
        }
    }
    @Published var sourcesData: [SourceJSON] = [] {
        didSet {
            updateSourcesApps()
        }
    }
    @Published var sourcesApps: [SourceAppsData] = []

    private var resolveTask: Task<Void, Never>?
    private var resolveGeneration = UUID()

    public func getEnabledSources() -> [SourceJSON] {
        return sourcesData.filter { sourceJSON in
            return sourcesList.contains { sourceData in
                sourceData.id == sourceJSON.id && sourceData.isEnabled
            }
        }
    }

    func enableSourceToggle(source: SourceData, value: Bool) {
        if let index = sourcesList.firstIndex(where: { $0.id == source.id }) {
            sourcesList[index].isEnabled = value
        }
        updateSourcesApps()
    }

    func updateSourcesApps() {
        var bundleIDs = Set<String>()
        sourcesApps = getEnabledSources().flatMap(\.data).filter {
            bundleIDs.insert($0.bundleID).inserted
        }
    }

    //
    func addSource(_ source: SourceData) {
        sourcesList.append(source)
        resolveSources()
    }

    //
    func deleteSource(_ selectedSource: inout Set<UUID>) {
        removeSources(ids: selectedSource)
        selectedSource.removeAll()
    }

    func removeSources(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        sourcesList.removeAll { ids.contains($0.id) }
        // Remove cached content immediately, even while offline or after deleting
        // the last source. Cancelled requests must not restore it later.
        sourcesData.removeAll { ids.contains($0.id) }
        resolveSources()
    }

    //
    func moveSourceUp(_ selectedSource: inout Set<UUID>) {
        let selected = sourcesList.filter {
            selectedSource.contains($0.id)
        }
        if let first = sourcesList.first,
           let data = selected.first {
            if data != first {
                if var index = sourcesList.firstIndex(of: data) {
                    index -= 1
                    sourcesList.removeAll {
                        selectedSource.contains($0.id)
                    }
                    sourcesList.insert(contentsOf: selected, at: index)
                }
                resolveSources()
            }
        }
    }

    //
    func moveSourceDown(_ selectedSource: inout Set<UUID>) {
        let selected = sourcesList.filter {
            selectedSource.contains($0.id)
        }

        if let last = sourcesList.last,
           let data = selected.first {
            if data != last {
                if var index = sourcesList.firstIndex(of: data) {
                    index += 1
                    sourcesList.removeAll {
                        selectedSource.contains($0.id)
                    }
                    sourcesList.insert(contentsOf: selected, at: index)
                }
                resolveSources()
            }
        }
    }

    //
    func resolveSources() {
        resolveTask?.cancel()
        resolveGeneration = UUID()
        let generation = resolveGeneration
        let sources = sourcesList
        let sourceIDs = Set(sources.map(\.id))
        sourcesData.removeAll { !sourceIDs.contains($0.id) }
        guard isConnected() && !sources.isEmpty else {
            resolveTask = nil
            return
        }
        sourcesData.removeAll()
        resolveTask = Task { @MainActor in

            for source in sources {
                guard !Task.isCancelled, generation == resolveGeneration,
                      let index = sourcesList.firstIndex(where: {
                          $0.id == source.id && $0.source == source.source
                      }) else { return }
                sourcesList[index].status = .checking
                let (sourceJson, sourceState) = await getSourceData(sourceLink: source.source, sourceId: source.id)
                guard !Task.isCancelled, generation == resolveGeneration,
                      let currentIndex = sourcesList.firstIndex(where: {
                          $0.id == source.id && $0.source == source.source
                      }) else { return }
                sourcesList[currentIndex].status = sourceState
                if sourceState == .valid, let sourceJson {
                    sourcesData.append(sourceJson)
                }
            }

        }
    }

    //
    func awaitResolveSources() async {
        guard let task = resolveTask else {
            return
        }
        _ = await task.result
    }

    //
    @discardableResult private func encode() -> Bool {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml

        do {
            let data = try encoder.encode(sourcesList)
            try data.write(to: plistSource, options: .atomic)
            return true
        } catch {
            print("StoreVM: Failed to encode Sources.plist! ", error)
            return false
        }
    }

    //
    @discardableResult private func decode() -> Bool {
        do {
            let data = try Data(contentsOf: plistSource)
            sourcesList = try PropertyListDecoder().decode([SourceData].self, from: data)
            return true
        } catch {
            print("StoreVM: Failed to decode Sources.plist! ", error)
            return false
        }
    }

    //
    private func getSourceData(sourceLink: String, sourceId: UUID) async -> (SourceJSON?, SourceValidation) {
        guard let url = URL(string: sourceLink) else { return (nil, .badurl) }
        var dataToDecode: Data?
        do {
            let (data, response) = try await loadData(
                URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
            )
            if !url.isFileURL {
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { return (nil, .badurl) }
            }
            dataToDecode = data
        } catch {
            debugPrint("Error decoding data from URL: \(url): \(error)")
            return (nil, .badjson)
        }
        guard let unwrappedData = dataToDecode else { return (nil, .badurl) }
        var decodedData: SourceJSON?
        do {
            let source = try JSONDecoder().decode(SourceJSON.self, from: unwrappedData)
            // Remote IDs are not unique across configured sources. Match decoded
            // content to the locally persisted identity used by selection/deletion.
            decodedData = SourceJSON(name: source.name, data: source.data, id: sourceId)
            return (decodedData, .valid)
        } catch {
            do {
                let sourceName = url.isFileURL
                ? (url.absoluteString as NSString).lastPathComponent.replacingOccurrences(of: ".json", with: "")
                : url.host ?? url.absoluteString
                let oldTypeJson: [SourceAppsData] = try JSONDecoder().decode([SourceAppsData].self, from: unwrappedData)
                decodedData = SourceJSON(name: sourceName, data: oldTypeJson, id: sourceId)
                return (decodedData, .valid)
            } catch {
                debugPrint("Error decoding data from URL: \(url): \(error)")
                return (nil, .badjson)
            }
        }
    }

}

// Source Data Structure
struct SourceJSON: Codable, Equatable, Hashable {
    let name: String
    let data: [SourceAppsData]
    let id: UUID
}

struct SourceAppsData: Codable, Equatable, Hashable {
    let bundleID: String
    let name: String
    let version: String
    let itunesLookup: String
    let link: String
    let checksum: String?
}
