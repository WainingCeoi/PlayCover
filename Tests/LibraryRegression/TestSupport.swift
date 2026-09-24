import AppKit
import Foundation

// Narrow stand-ins for installation, logging, third-party caching and private
// CoreUI. Tests never modify the user's installed apps or call private CoreUI.
enum PlayTools {
    static let playCoverContainer = FileManager.default.temporaryDirectory
        .appendingPathComponent("PlayCoverLibraryTests-\(UUID().uuidString)")
    static func installOnSystem() {}
}

final class Log {
    static let shared = Log()
    func error(_ error: Error) { fatalError("Unexpected library error: \(error)") }
}

final class PlayApp {
    static let bundleIDCacheURL = PlayTools.playCoverContainer.appendingPathComponent("CACHE")
    static var bundleIDCache: [String] {
        get throws {
            try String(contentsOf: bundleIDCacheURL, encoding: .utf8)
                .split(whereSeparator: \.isNewline).map(String.init)
        }
    }
    static var initializationCount = 0
    static var initializedOnMainThread = false
    let url: URL
    let info: AppInfo
    var isStarting = false
    var hasActiveSession = false

    init(appUrl: URL) {
        Self.initializationCount += 1
        Self.initializedOnMainThread = Self.initializedOnMainThread || Thread.isMainThread
        // Represent the filesystem work done when preparing a real installed app.
        Thread.sleep(forTimeInterval: 0.03)
        url = appUrl
        info = AppInfo(contentsOf: appUrl.appendingPathComponent("Info.plist"))
    }

    var name: String { info.displayName.isEmpty ? info.bundleName : info.displayName }
    var searchText: String { "\(info.displayName) \(info.bundleName)".lowercased() }
}

final class DataCache {
    static let instance = DataCache()
    var images: [String: NSImage] = [:]
    var deferWrites = false
    func readImage(forKey key: String) -> NSImage? { images[key] }
    func write(image: NSImage, forKey key: String) {
        if !deferWrites { images[key] = image }
    }
    func write<T: Encodable>(codable: T, forKey key: String) throws {}
}

@propertyWrapper struct ImageCache {
    var wrappedValue = MemoryImageCache()
}

struct MemoryImageCache {
    func setCacheLimit(countLimit: Int, totalCostLimit: Int) {}
    func removeCache() {}
}

struct ITunesResponse: Codable {}
func getITunesData(_ link: String) async -> ITunesResponse? { nil }

final class CUICatalog {
    static var requestedNames: [String] = []
    init(url: URL) throws {}
    func allImageNames() -> [String] { ["GameTexture", "AppIcon60x60", "LaunchBackground"] }
    func images(withName name: String) -> [Any] {
        Self.requestedNames.append(name)
        return [CUINamedImage()]
    }
}

final class CUINamedImage {
    func _rendition() -> TestRendition { TestRendition() }
}

struct TestRendition {
    func unslicedImage() -> Unmanaged<CGImage>? { nil }
}
