import Foundation

enum InstallationTransaction {
    /// Finish preparation on the destination volume before replacing a working installation.
    @discardableResult
    static func replace(at destination: URL, with source: URL,
                        prepare: (URL) throws -> Void = { _ in }) throws -> URL {
        let manager = FileManager.default
        let staging = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                      appropriateFor: destination, create: true)
        defer { try? manager.removeItem(at: staging) }
        let candidate = staging.appendingPathComponent(destination.lastPathComponent)
        try manager.moveItem(at: source, to: candidate)
        try prepare(candidate)

        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: candidate,
                                          options: .usingNewMetadataOnly)
        } else {
            try manager.moveItem(at: candidate, to: destination)
        }
        return destination
    }
}
