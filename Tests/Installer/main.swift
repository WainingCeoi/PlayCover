import Foundation

enum FixtureError: Error { case signingFailed }

// Execute the production archive helper's commands without loading the application's logging/UI layer.
enum Shell {
    @discardableResult
    static func run(_ binary: String, _ arguments: String...) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw FixtureError.signingFailed }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

let manager = FileManager.default
let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try manager.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: root) }

func app(_ name: String, contents: String) throws -> URL {
    let url = root.appendingPathComponent(name)
    try manager.createDirectory(at: url, withIntermediateDirectories: true)
    try Data(contents.utf8).write(to: url.appendingPathComponent("executable"))
    return url
}

func contents(_ app: URL) throws -> String {
    String(data: try Data(contentsOf: app.appendingPathComponent("executable")), encoding: .utf8) ?? ""
}

let installed = try app("installed.app", contents: "original")
let badUpdate = try app("failed-update.app", contents: "unsigned")
var candidateURL: URL?
do {
    try InstallationTransaction.replace(at: installed, with: badUpdate) { candidate in
        candidateURL = candidate
        let previous = try contents(installed)
        precondition(previous == "original")
        throw FixtureError.signingFailed
    }
    fatalError("Failed signing was accepted")
} catch FixtureError.signingFailed { }
let original = try contents(installed)
precondition(original == "original", "A failed update destroyed the working installation")
guard let failedCandidate = candidateURL else { fatalError("Preparation was not called") }
precondition(!manager.fileExists(atPath: failedCandidate.path), "Failed staging was not cleaned up")

let update = try app("update.app", contents: "unsigned")
try InstallationTransaction.replace(at: installed, with: update) { candidate in
    candidateURL = candidate
    let previous = try contents(installed)
    precondition(previous == "original", "Old installation disappeared before signing completed")
    try Data("signed".utf8).write(to: candidate.appendingPathComponent("executable"))
}
let updated = try contents(installed)
precondition(updated == "signed", "Prepared update was not committed")
guard let successfulCandidate = candidateURL else { fatalError("Preparation was not called") }
precondition(!manager.fileExists(atPath: successfulCandidate.path), "Successful staging was not cleaned up")

let newApp = try app("new.app", contents: "first-install")
let newDestination = root.appendingPathComponent("first-install.app")
try InstallationTransaction.replace(at: newDestination, with: newApp)
let firstInstall = try contents(newDestination)
precondition(firstInstall == "first-install", "First installation failed")

let exportDestination = root.appendingPathComponent("Export.ipa")
let freshExport = root.appendingPathComponent("Fresh.ipa")
try Data("old-archive".utf8).write(to: exportDestination)
try Data("fresh-archive".utf8).write(to: freshExport)
try InstallationTransaction.replace(at: exportDestination, with: freshExport)
let exported = try Data(contentsOf: exportDestination)
precondition(exported == Data("fresh-archive".utf8), "Archive replacement preserved stale content")

let payload = root.appendingPathComponent("Payload")
let exportApp = payload.appendingPathComponent("Space Name.app")
try manager.createDirectory(at: exportApp, withIntermediateDirectories: true)
let obsolete = exportApp.appendingPathComponent("obsolete")
try Data("old".utf8).write(to: obsolete)
_ = try IPAArchive.pack(app: exportApp, destination: exportDestination)
let originalEntries = try Shell.run("/usr/bin/unzip", "-Z1", exportDestination.path)
precondition(originalEntries.contains("Payload/Space Name.app/obsolete"), "IPA does not have a Payload root")
precondition(!originalEntries.contains(root.path), "IPA contains an absolute filesystem path")
try manager.removeItem(at: obsolete)
try Data("new".utf8).write(to: exportApp.appendingPathComponent("executable"))
_ = try IPAArchive.pack(app: exportApp, destination: exportDestination)
let newEntries = try Shell.run("/usr/bin/unzip", "-Z1", exportDestination.path)
precondition(newEntries.contains("Payload/Space Name.app/executable"), "New export content is missing")
precondition(!newEntries.contains("obsolete"), "Re-export retained deleted archive entries")
let archiveContents = try Shell.run("/usr/bin/unzip", "-p", exportDestination.path,
                                   "Payload/Space Name.app/executable")
precondition(archiveContents == "new", "Exported file contents changed")
print("Installer transaction regression checks passed")
