import Foundation

enum IPAArchive {
    static func pack(app: URL, destination: URL) throws -> URL {
        let manager = FileManager.default
        let archiveDirectory = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                appropriateFor: destination, create: true)
        defer { try? manager.removeItem(at: archiveDirectory) }
        let archive = archiveDirectory.appendingPathComponent("Export.ipa")
        // A fresh archive avoids stale entries on re-export. keepParent makes Payload the ZIP root.
        try Shell.run("/usr/bin/ditto", "-c", "-k", "--norsrc", "--noextattr", "--noqtn",
                      "--keepParent", app.deletingLastPathComponent().path, archive.path)
        return try InstallationTransaction.replace(at: destination, with: archive)
    }
}
