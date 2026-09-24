//
//  PlayApp.swift
//  PlayCover
//

import Cocoa
import Foundation
import IOKit.pwr_mgt

class PlayApp: BaseApp {
    // MARK: - Static
    public static let bundleIDCacheURL = PlayTools.playCoverContainer.appendingPathComponent("CACHE")

    public static var bundleIDCache: [String] {
        get throws {
            (try String(contentsOf: bundleIDCacheURL, encoding: .utf8))
                .split(whereSeparator: \.isNewline)
                .map { String($0) }
        }
    }

    // MARK: - Instance State
    var displaySleepAssertionID: IOPMAssertionID?
    private let launchLock = NSLock()
    private var starting = false
    public var isStarting: Bool {
        launchLock.lock()
        defer { launchLock.unlock() }
        return starting
    }
    @MainActor private var monitoredApp: NSRunningApplication?
    @MainActor var hasActiveSession: Bool { monitoredApp?.isTerminated == false }
    var sessionDisableKeychain: Bool = false

    // MARK: - Init
    override convenience init(appUrl: URL) {
        self.init(appUrl: appUrl, prepareForLaunch: true)
    }

    init(appUrl: URL, prepareForLaunch: Bool) {
        super.init(appUrl: appUrl)
        guard prepareForLaunch else { return }

        keymapping.reloadKeymapCache()

        createAlias()

        loadDiscordIPC()
    }

    // MARK: - Computed
    var searchText: String {
        info.displayName.lowercased()
            .appending(" ")
            .appending(info.bundleName)
            .lowercased()
    }

    var name: String {
        info.displayName.isEmpty ? info.bundleName : info.displayName
    }

    // MARK: - Paths / Singletons
    static let aliasDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications")
        .appendingPathComponent("PlayCover")

    lazy var aliasURL = PlayApp.aliasDirectory.appendingPathComponent(name).appendingPathExtension("app")
    lazy var playChainURL = KeyCover.playChainPath.appendingPathComponent(info.bundleIdentifier)

    lazy var settings = AppSettings(info)
    lazy var keymapping = Keymapping(info)
    lazy var container = AppContainer(bundleId: info.bundleIdentifier)

    // MARK: - Launch
    private func beginLaunch() -> Bool {
        launchLock.lock()
        defer { launchLock.unlock() }
        guard !starting else { return false }
        starting = true
        return true
    }

    private func finishLaunch() {
        launchLock.lock()
        defer { launchLock.unlock() }
        starting = false
    }

    func launch() async {
        guard beginLaunch() else { return }
        defer { finishLaunch() }
        var keyCoverUnlocked = false
        do {
            if prohibitedToPlay {
                await clearAllCache()
                throw PlayCoverError.appProhibited
            } else if maliciousProhibited {
                await clearAllCache()
                deleteApp()
                throw PlayCoverError.appMaliciousProhibited
            }

            if await VersionCheck.shared.checkNewVersion(myApp: self) { return }

            try prepareLaunch()
            await unlockKeyCover()
            keyCoverUnlocked = true
            clearDebugAffectingEnvironment()

            if settings.openWithLLDB {
                try Shell.lldb(executable, withTerminalWindow: settings.openLLDBWithTerminal)
            } else {
                try await runAppExec()
            }
            keyCoverUnlocked = false
        } catch {
            Log.shared.error(error)
        }
        if keyCoverUnlocked { lockKeyCover() }
    }

    private func prepareLaunch() throws {
        settings.sync()
        // Finish plugin installation before sealing the bundle signature.
        if hasPlayTools() {
            try PlayTools.installPluginInIPA(url)
        }
        if try !Entitlements.areEntitlementsValid(app: self) {
            try sign()
        }
        if try !isInfoPlistSigned() {
            try Shell.signApp(executable)
        }
        // Refresh the LaunchServices target after all plist and signature changes.
        try refreshAlias()
        guard try PlayTools.isInstalled() else {
            throw "PlayTools are not installed! Please move PlayCover.app into Applications!"
        }
        guard try Macho.isMachoValidArch(executable) else {
            throw "The app threw an error during conversion."
        }
    }
}

// MARK: - Environment Management
extension PlayApp {
    static let introspection: String = "/usr/lib/system/introspection"
    static let iosFrameworks: String = "/System/iOSSupport/System/Library/Frameworks"

    /// Common Metal and capture related environment keys used in multiple places
    private static let metalEnvKeys: [String] = [
        "METAL_DEVICE_WRAPPER_TYPE",
        "METAL_DEBUG_LAYER",
        "MTL_DEBUG_LAYER",
        "METAL_API_VALIDATION",
        "METAL_SHADER_VALIDATION",
        "METAL_SHADER_VALIDATION_OPTIONS",
        "METAL_CAPTURE_ENABLED",
        "METAL_CAPTURE_OUTPUT_FILE",
        "METAL_CAPTURE_TYPE",
        "METAL_FORCE_LAZY_COMPILATION",
        "METAL_FRAME_CAPTURE_ENABLED",
        "METAL_ERROR_MODE",
        "MTLCaptureEnabled"
    ]

    // clear environment variables that can force debug wrappers or validation layers
    func clearDebugAffectingEnvironment() {
        // Clear DYLD_* variables inherited from Xcode or other debuggers
        for (key, _) in ProcessInfo.processInfo.environment where key.hasPrefix("DYLD_") {
            unsetenv(key)
        }

        // Clear common Metal debug and capture related variables
        for key in PlayApp.metalEnvKeys {
            unsetenv(key)
        }
    }

    @MainActor
    func runAppExec() async throws {
        let config = NSWorkspace.OpenConfiguration()

        // Prevent propagating debugging-related variables to child process
        for (key, _) in ProcessInfo.processInfo.environment where key.hasPrefix("DYLD_") {
            unsetenv(key)
        }
        for key in PlayApp.metalEnvKeys {
            unsetenv(key)
        }

        let runningApp = try await NSWorkspace.shared.openApplication(at: aliasURL, configuration: config)
        // Opening an already-running app activates it; keep its existing session monitor.
        guard monitoredApp?.processIdentifier != runningApp.processIdentifier else { return }
        monitoredApp = runningApp
        Task { @MainActor in
            defer {
                // A quick relaunch can replace the session during the keychain grace period.
                if self.monitoredApp === runningApp {
                    self.enableTimeOut()
                    self.monitoredApp = nil
                    self.lockKeyCover()
                }
            }
            while self.monitoredApp === runningApp && !runningApp.isTerminated {
                if runningApp.isActive {
                    self.disableTimeOut()
                } else {
                    self.enableTimeOut()
                }
                // Suspend instead of blocking a cooperative executor thread for the session's lifetime.
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
            }
            if self.monitoredApp === runningApp { self.enableTimeOut() }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}

// MARK: - Management
extension PlayApp {
    func disableTimeOut() {
        if displaySleepAssertionID != nil { return }

        let reason = "PlayCover: \(info.bundleIdentifier) is disabling sleep" as CFString
        var assertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        if result == kIOReturnSuccess {
            displaySleepAssertionID = assertionID
        }
    }

    func enableTimeOut() {
        if let assertionID = displaySleepAssertionID {
            IOPMAssertionRelease(assertionID)
            displaySleepAssertionID = nil
        }
    }
}

// MARK: - KeyCover
extension PlayApp {
    func unlockKeyCover() async {
        if KeyCover.shared.isKeyCoverEnabled() {
            let keychain = KeyCover.shared.listKeychains()
                .first(where: { $0.appBundleID == self.info.bundleIdentifier })

            if let keychain = keychain, keychain.chainEncryptionStatus {
                try? await KeyCover.shared.unlockChain(keychain)

                if KeyCover.shared.keyCoverPlainTextKey == nil {
                    // Pop an alert telling the user that keychain was not unlocked
                    // and keychain is disabled for the session
                    Task { @MainActor in
                        let alert = NSAlert()
                        alert.messageText = NSLocalizedString("keycover.alert.title", comment: "")
                        alert.informativeText = NSLocalizedString("keycover.alert.content", comment: "")
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: NSLocalizedString("button.OK", comment: ""))
                        alert.runModal()
                    }
                    settings.settings.playChain = false
                    sessionDisableKeychain = true
                }
            }
        }
    }

    func lockKeyCover() {
        if KeyCover.shared.isKeyCoverEnabled() {
            if sessionDisableKeychain {
                settings.settings.playChain = true
                sessionDisableKeychain = false
                return
            }

            let keychain = KeyCover.shared.listKeychains()
                .first(where: { $0.appBundleID == self.info.bundleIdentifier })

            if let keychain = keychain, !keychain.chainEncryptionStatus {
                try? KeyCover.shared.lockChain(keychain)
            }
        }
    }
}

// MARK: - Tools
extension PlayApp {
    func hasPlayTools() -> Bool {
        do {
            return try PlayTools.installedInExec(atURL: url.appendingEscapedPathComponent(info.executableName))
        } catch {
            Log.shared.error(error)
            return true
        }
    }

    func changeDyldLibraryPath(set: Bool? = nil, path: String) async -> Bool {
        info.lsEnvironment["DYLD_LIBRARY_PATH"] = info.lsEnvironment["DYLD_LIBRARY_PATH"] ?? ""

        if let set = set {
            if set {
                info.lsEnvironment["DYLD_LIBRARY_PATH"]? += "\(path):"
            } else {
                info.lsEnvironment["DYLD_LIBRARY_PATH"] = info.lsEnvironment["DYLD_LIBRARY_PATH"]?
                    .replacingOccurrences(of: "\(path):", with: "")
            }

            do {
                try Shell.signApp(executable)
            } catch {
                Log.shared.error(error)
            }
        }

        guard let result = info.lsEnvironment["DYLD_LIBRARY_PATH"] else {
            return false
        }
        return result.contains(path)
    }
}

// MARK: - FS / Codesign
extension PlayApp {
    func hasAlias() -> Bool {
        FileManager.default.fileExists(atPath: aliasURL.path)
    }

    func isInfoPlistSigned() throws -> Bool {
        try Shell.run("/usr/bin/codesign", "-dv", executable.path).contains("Info.plist entries")
    }

    func showInFinder() {
        URL(fileURLWithPath: url.path).showInFinderAndSelectLastComponent()
    }

    func openAppCache() {
        container.containerUrl.showInFinderAndSelectLastComponent()
    }

    func clearAllCache() async {
        Uninstaller.clearExternalCache(info.bundleIdentifier)
    }

    func clearPlayChain() {
        FileManager.default.delete(at: playChainURL)
        FileManager.default.delete(at: playChainURL.appendingPathExtension("keyCover"))
        FileManager.default.delete(at: playChainURL.appendingPathExtension("db"))
    }

    func deleteApp() {
        FileManager.default.delete(at: URL(fileURLWithPath: url.path))
        AppsVM.shared.fetchApps()
    }

    func sign() throws {
        let tmpEnts = FileManager.default.temporaryDirectory
            .appendingEscapedPathComponent(ProcessInfo().globallyUniqueString)
            .appendingPathExtension("plist")
        defer { try? FileManager.default.removeItem(at: tmpEnts) }
        let conf = try Entitlements.composeEntitlements(self)
        try conf.store(tmpEnts)
        try Shell.signAppWith(executable, entitlements: tmpEnts)
    }
}
