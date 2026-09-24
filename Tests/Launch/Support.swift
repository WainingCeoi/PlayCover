// Test doubles keep launch regression checks independent of downloaded packages and user data.
@_exported import Cocoa

final class Log {
    static let shared = Log()
    func log(_ message: String) { }
    func error(_ error: Error) { }
}
final class AppSettings {
    var settings = Values()
    var openWithLLDB = false
    var openLLDBWithTerminal = false
    struct Values {
        var playChain = true
        var discordActivity = Activity()
    }
    struct Activity { var enable = false }
    init(_ info: AppInfo) { }
    func sync() { }
}
final class Keymapping {
    init(_ info: AppInfo) { }
    func reloadKeymapCache() { }
}
final class AppContainer {
    var containerUrl = FileManager.default.temporaryDirectory
    init(bundleId: String) { }
    func doesExist() -> Bool { false }
}
final class PlayTools {
    static let playCoverContainer = FileManager.default.temporaryDirectory
    static func installPluginInIPA(_ url: URL) throws { }
    static func isInstalled() throws -> Bool { true }
    static func installedInExec(atURL url: URL) throws -> Bool { false }
}
final class Macho {
    static func isMachoValidArch(_ url: URL) throws -> Bool { true }
}
final class VersionCheck {
    static let shared = VersionCheck()
    var abortLaunch = false
    func checkNewVersion(myApp: PlayApp) async -> Bool { abortLaunch }
}
final class KeyCover {
    static let shared = KeyCover()
    static let playChainPath = FileManager.default.temporaryDirectory
    var keyCoverPlainTextKey: String?
    struct Chain {
        var appBundleID: String
        var chainEncryptionStatus: Bool
    }
    func isKeyCoverEnabled() -> Bool { false }
    func listKeychains() -> [Chain] { [] }
    func unlockChain(_ chain: Chain) async throws { }
    func lockChain(_ chain: Chain) throws { }
}
final class AppsVM {
    static let shared = AppsVM()
    func fetchApps() { }
}
final class Uninstaller {
    static func clearExternalCache(_ id: String) { }
}
final class Entitlements {
    static let playCoverEntitlementsDir = FileManager.default.temporaryDirectory
    static var failValidation = false
    static func areEntitlementsValid(app: PlayApp) throws -> Bool {
        if failValidation { throw NSError(domain: "LaunchRegression", code: 1) }
        return true
    }
    static func composeEntitlements(_ app: PlayApp) throws -> [String: Any] { [:] }
}
extension Dictionary {
    func store(_ url: URL) throws {
        try PropertyListSerialization.data(fromPropertyList: self, format: .xml, options: 0).write(to: url)
    }
}
