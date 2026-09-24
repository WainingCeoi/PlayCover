//
//  PlayAppExtensions.swift
//  PlayCover
//
//  Created by TheMoonThatRises on 10/2/23.
//

import Foundation

extension PlayApp {
    func loadDiscordIPC() {
        if self.container.doesExist() {
            let appTmp = self.container.containerUrl.appendingPathComponent("Data")
                .appendingPathComponent("tmp")

            try? FileManager.default.createDirectory(at: appTmp, withIntermediateDirectories: false)

            appTmp.enumerateContents { url, _ in
                if url.lastPathComponent.range(of: "discord-ipc-[0-9]", options: .regularExpression) != nil {
                    do {
                        try FileManager.default.removeItem(at: url)
                    } catch {
                        print("failed to remove discord ipc: \(error)")
                    }
                }
            }

            guard self.settings.settings.discordActivity.enable else {
                return
            }

            let userTmp = FileManager.default.temporaryDirectory.path

            for ipcPort in 0..<10 {
                let socketPath = userTmp + "/discord-ipc-\(ipcPort)"
                if FileManager.default.fileExists(atPath: socketPath) {
                    do {
                        try FileManager.default.createSymbolicLink(atPath: appTmp
                            .appendingPathComponent("discord-ipc-\(ipcPort)").path,
                                                                   withDestinationPath: socketPath)
                        print("Successfully linked discordipc for \(self.info.bundleIdentifier)")
                        return
                    } catch {
                        print(error)
                        continue
                    }
                }
            }

            print("Unable to link discordipc for \(self.info.bundleIdentifier)")
        }
    }

    func createAlias() {
        do {
            try refreshAlias()
        } catch {
            Log.shared.log(error.localizedDescription)
        }
    }

    /// Refresh after the real bundle has been finalized and signed, before LaunchServices opens it.
    func refreshAlias() throws {
        try Self.refreshAlias(from: url, to: aliasURL)
    }

    static func refreshAlias(from source: URL, to alias: URL) throws {
        let source = source.resolvingSymlinksInPath()
        let manager = FileManager.default
        let sourceInfo = source.appendingPathComponent("Info.plist")
        // Read first so a missing or unreadable source cannot destroy a working alias.
        let infoData = try Data(contentsOf: sourceInfo)
        let contents = try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        try manager.createDirectory(at: alias, withIntermediateDirectories: true)

        let names = Set(contents.map(\.lastPathComponent))
        for item in try manager.contentsOfDirectory(at: alias, includingPropertiesForKeys: nil)
            where !names.contains(item.lastPathComponent) {
            // Prune obsolete links owned by the alias, including dangling links after an update.
            if let target = try? manager.destinationOfSymbolicLink(atPath: item.path),
               URL(fileURLWithPath: target).lastPathComponent == item.lastPathComponent,
               URL(fileURLWithPath: target).deletingLastPathComponent().resolvingSymlinksInPath() == source {
                try manager.removeItem(at: item)
            }
        }

        for item in contents where item.lastPathComponent != "Info.plist" {
            let destination = alias.appendingPathComponent(item.lastPathComponent)
            if (try? manager.destinationOfSymbolicLink(atPath: destination.path)) == item.path {
                continue
            }
            if (try? manager.attributesOfItem(atPath: destination.path)) != nil {
                try manager.removeItem(at: destination)
            }
            try manager.createSymbolicLink(at: destination, withDestinationURL: item)
        }

        let aliasInfo = alias.appendingPathComponent("Info.plist")
        if (try? manager.destinationOfSymbolicLink(atPath: aliasInfo.path)) != nil {
            try manager.removeItem(at: aliasInfo)
        }
        // macOS 27 rejects a symlink or a copy predating the bundle's code signature (-54).
        // An atomic write also prevents readers from observing a partially copied plist.
        if (try? Data(contentsOf: aliasInfo)) != infoData {
            try infoData.write(to: aliasInfo, options: .atomic)
        }
    }

    func removeAlias() {
        FileManager.default.delete(at: aliasURL)
    }
}

// MARK: - Policies
extension PlayApp {
    var prohibitedToPlay: Bool {
        PlayApp.PROHIBITED_APPS.contains(info.bundleIdentifier)
    }

    var maliciousProhibited: Bool {
        PlayApp.MALICIOUS_APPS.contains(info.bundleIdentifier)
    }

    static let PROHIBITED_APPS = [
        "com.activision.callofduty.shooter",
        "com.ea.ios.apexlegendsmobilefps",
        "com.tencent.tmgp.cod",
        "com.tencent.ig",
        "com.pubg.newstate",
        "com.pubg.imobile",
        "com.tencent.tmgp.pubgmhd",
        "com.dts.freefireth",
        "com.dts.freefiremax",
        "vn.vng.codmvn",
        "com.ngame.allstar.eu",
        "com.axlebolt.standoff2",
        "com.tencent.lolm"
    ]

    static let MALICIOUS_APPS = [
        "com.zhiliaoapp.musically"
    ]
}
