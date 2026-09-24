import Foundation

func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw NSError(domain: message, code: 1) }
}

let manager = FileManager.default
let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try manager.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: root) }
let source = root.appendingPathComponent("Source.app")
let alias = root.appendingPathComponent("Alias.app")
try manager.createDirectory(at: source, withIntermediateDirectories: true)
let executable = source.appendingPathComponent("Fixture")
try manager.copyItem(at: URL(fileURLWithPath: CommandLine.arguments[1]), to: executable)
let info = source.appendingPathComponent("Info.plist")
let aliasInfo = alias.appendingPathComponent("Info.plist")
var values: [String: Any] = [
    "CFBundleIdentifier": "io.playcover.regression.fixture",
    "CFBundleExecutable": "Fixture",
    "CFBundleName": "Fixture",
    "CFBundlePackageType": "APPL",
    "CFBundleVersion": "1"
]
func writeInfo() throws {
    try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        .write(to: info, options: .atomic)
}
try writeInfo()
try PlayApp.refreshAlias(from: source, to: alias)
let executableLink = try manager.destinationOfSymbolicLink(atPath: alias.appendingPathComponent("Fixture").path)
try require(URL(fileURLWithPath: executableLink).resolvingSymlinksInPath()
            == executable.resolvingSymlinksInPath(), "Executable must be linked")
try require((try? manager.destinationOfSymbolicLink(atPath: aliasInfo.path)) == nil,
            "Info.plist must be a real file")

// Reproduce first launch after installation: alias exists BEFORE final plist changes and signing.
values["LSEnvironment"] = ["FIXTURE": "after signing"]
try writeInfo()
try Shell.run(print: false, "/usr/bin/codesign", "--force", "--sign", "-", source.path)
try require(try Data(contentsOf: info) != Data(contentsOf: aliasInfo), "Fixture must begin with stale alias metadata")
try PlayApp.refreshAlias(from: source, to: alias)
try require(try Data(contentsOf: info) == Data(contentsOf: aliasInfo), "Alias must match the signed source bytes")
let signature = try Shell.run(print: false, "/usr/bin/codesign", "-dv", alias.path)
try require(signature.contains("Info.plist entries="), "Alias Info.plist must be bound to the code signature")
try require(manager.fileExists(atPath: alias.appendingPathComponent("_CodeSignature").path),
            "Signature directory added after initial alias must be linked")

// Existing correct aliases are cheap to refresh; do not rewrite metadata on every launch.
let oldAttributes = try manager.attributesOfItem(atPath: aliasInfo.path)
try PlayApp.refreshAlias(from: source, to: alias)
let newAttributes = try manager.attributesOfItem(atPath: aliasInfo.path)
try require((oldAttributes[.systemFileNumber] as? NSNumber) == (newAttributes[.systemFileNumber] as? NSNumber),
            "Unchanged metadata should retain its inode")

// Migrate a pre-macOS 27 alias whose metadata was a symlink, without changing the real plist.
try manager.removeItem(at: aliasInfo)
try manager.createSymbolicLink(at: aliasInfo, withDestinationURL: info)
let beforeMigration = try Data(contentsOf: info)
try PlayApp.refreshAlias(from: source, to: alias)
try require((try? manager.destinationOfSymbolicLink(atPath: aliasInfo.path)) == nil, "Legacy symlink must be replaced")
try require(try Data(contentsOf: info) == beforeMigration, "Migration must preserve the signed source plist")

// Removed bundle files must not leave dangling links in the launch target.
let obsolete = source.appendingPathComponent("Obsolete")
try Data([1, 2, 3]).write(to: obsolete)
try PlayApp.refreshAlias(from: source, to: alias)
try manager.removeItem(at: obsolete)
try PlayApp.refreshAlias(from: source, to: alias)
try require((try? manager.destinationOfSymbolicLink(atPath: alias.appendingPathComponent("Obsolete").path)) == nil,
            "Removed source files must not leave stale alias links")

// Missing source metadata must fail loudly and preserve the last working alias.
let app = PlayApp(appUrl: source, prepareForLaunch: false)
app.aliasURL = alias
VersionCheck.shared.abortLaunch = true
await app.launch()
try require(!app.isStarting, "Version-check early return must clear launch state")
VersionCheck.shared.abortLaunch = false
Entitlements.failValidation = true
await app.launch()
try require(!app.isStarting, "Thrown preparation error must clear launch state for retries")

let beforeFailure = try Data(contentsOf: aliasInfo)
try manager.removeItem(at: info)
var didFail = false
do { try PlayApp.refreshAlias(from: source, to: alias) } catch { didFail = true }
try require(didFail, "Missing source plist must propagate an error")
try require(try Data(contentsOf: aliasInfo) == beforeFailure, "Failed refresh must preserve alias metadata")

print("PASS: signed alias refresh, legacy migration, idempotence, added/removed entries, "
      + "failure preservation, launch reset")
