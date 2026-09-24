import Foundation
import MachO

// Compile the production parser without the app or third-party dependencies.
enum PlayCoverError: Error {
    case appCorrupted
    case failedToStripBinary
}

func bytes<T>(_ value: T) -> Data {
    withUnsafeBytes(of: value) { Data($0) }
}

func executable(_ commands: [Data], padding: Int = 64, swapped: Bool = false) -> Data {
    var header = mach_header_64(magic: MH_MAGIC_64, cputype: CPU_TYPE_ARM64,
                               cpusubtype: 0, filetype: UInt32(MH_EXECUTE),
                               ncmds: UInt32(commands.count),
                               sizeofcmds: UInt32(commands.reduce(0) { $0 + $1.count }), flags: 0, reserved: 0)
    if swapped { swap_mach_header_64(&header, NX_BigEndian) }
    return commands.reduce(bytes(header)) { $0 + $1 } + Data(count: padding)
}

func version(swapped: Bool = false) -> Data {
    var command = version_min_command(cmd: UInt32(LC_VERSION_MIN_IPHONEOS), cmdsize: 16,
                                      version: 0x00120000, sdk: 0x00120000)
    if swapped { swap_version_min_command(&command, NX_BigEndian) }
    return bytes(command)
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

func rejects(_ message: String, _ action: () throws -> Void) {
    do {
        try action()
        fatalError("Accepted malformed Mach-O: \(message)")
    } catch { }
}

func validate(_ data: Data) throws {
    _ = try Macho.iterateLoadCommands(binary: data) { _, _ in false }
}

// Unaligned Data storage and invalid UTF-8 cannot trap the importer.
let unaligned = Data([0, 1, 2, 3, 4])
check(unaligned.extract(UInt32.self, offset: 1) == 0x04030201, "Unaligned load changed bytes")
check(String(data: Data([255, 0]), offset: 0, commandSize: 2,
             loadCommandString: lc_str(offset: 0)).isEmpty, "Invalid UTF-8 accepted")
check(String(data: Data([0]), offset: 0, commandSize: 1,
             loadCommandString: lc_str(offset: 2)).isEmpty, "Invalid string offset accepted")

for size in 0..<MemoryLayout<mach_header_64>.size {
    rejects("truncated header \(size)") { try validate(Data(count: size)) }
}
rejects("bad magic") { try validate(Data(count: 128)) }
rejects("truncated fat table") {
    var binary = bytes(fat_header(magic: FAT_MAGIC, nfat_arch: UInt32.max))
    try Macho.stripBinary(&binary)
}

let thin = executable([version()])
for is64Bit in [false, true] {
    for swapped in [false, true] {
        let sliceOffset = MemoryLayout<fat_header>.size
            + (is64Bit ? MemoryLayout<fat_arch_64>.size : MemoryLayout<fat_arch>.size)
        var header = fat_header(magic: is64Bit ? FAT_MAGIC_64 : FAT_MAGIC, nfat_arch: 1)
        if swapped { swap_fat_header(&header, NX_BigEndian) }
        var binary = bytes(header)
        if is64Bit {
            var arch = fat_arch_64(cputype: CPU_TYPE_ARM64, cpusubtype: 0,
                                   offset: UInt64(sliceOffset), size: UInt64(thin.count), align: 0, reserved: 0)
            if swapped { swap_fat_arch_64(&arch, 1, NX_BigEndian) }
            binary += bytes(arch)
        } else {
            var arch = fat_arch(cputype: CPU_TYPE_ARM64, cpusubtype: 0,
                                offset: UInt32(sliceOffset), size: UInt32(thin.count), align: 0)
            if swapped { swap_fat_arch(&arch, 1, NX_BigEndian) }
            binary += bytes(arch)
        }
        binary += thin
        try Macho.stripBinary(&binary)
        check(binary == thin, "Wrong universal slice")
    }
}
rejects("overflowing FAT64 slice") {
    var binary = bytes(fat_header(magic: FAT_MAGIC_64, nfat_arch: 1))
        + bytes(fat_arch_64(cputype: CPU_TYPE_ARM64, cpusubtype: 0,
                            offset: UInt64.max, size: UInt64.max, align: 0, reserved: 0))
    try Macho.stripBinary(&binary)
}

for size in [0, 4, 12, UInt32.max] as [UInt32] {
    rejects("invalid command size \(size)") {
        try validate(executable([bytes(load_command(cmd: UInt32(LC_UUID), cmdsize: size))]))
    }
}
for command in [UInt32(LC_SEGMENT_64), UInt32(LC_LOAD_DYLIB), UInt32(LC_ENCRYPTION_INFO_64),
                UInt32(LC_BUILD_VERSION), UInt32(LC_VERSION_MIN_IPHONEOS)] {
    rejects("truncated command \(command)") {
        try validate(executable([bytes(load_command(cmd: command, cmdsize: 8))]))
    }
}
rejects("invalid dylib string offset") {
    let command = dylib_command(cmd: UInt32(LC_LOAD_DYLIB), cmdsize: 24,
                               dylib: dylib(name: lc_str(offset: 100), timestamp: 0,
                                            current_version: 0, compatibility_version: 0))
    try validate(executable([bytes(command)]))
}
rejects("unterminated dylib string") {
    let command = dylib_command(cmd: UInt32(LC_LOAD_DYLIB), cmdsize: 32,
                               dylib: dylib(name: lc_str(offset: 24), timestamp: 0,
                                            current_version: 0, compatibility_version: 0))
    try validate(executable([bytes(command) + Data(repeating: 65, count: 8)]))
}
rejects("inconsistent load command count") {
    var binary = thin
    var header = binary.extract(mach_header_64.self)
    header.ncmds += 1
    binary.replaceSubrange(0..<32, with: bytes(header))
    try validate(binary)
}
try validate(executable([version()], padding: 0))

for swapped in [false, true] {
    var binary = executable([version(swapped: swapped)], swapped: swapped)
    try Macho.replaceVersionCommand(&binary)
    try validate(binary)
    let header = binary.extract(mach_header_64.self, swap: swapped ? swap_mach_header_64:nil)
    let command = binary.extract(build_version_command.self, offset: 32,
                                 swap: swapped ? swap_build_version_command:nil)
    check(header.ncmds == 1 && header.sizeofcmds == 24, "Header was not preserved")
    check(command.platform == UInt32(PLATFORM_MACCATALYST), "Wrong output platform")
}
var missingVersion = executable([bytes(load_command(cmd: UInt32(LC_PREBIND_CKSUM), cmdsize: 8))])
try Macho.replaceVersionCommand(&missingVersion)
check(missingVersion.extract(mach_header_64.self).ncmds == 2, "Added command was not counted")
try validate(missingVersion)

// A larger dylib path must shift following commands, while preserving the file payload.
let oldLibrary = "@rpath/libswiftUIKit.dylib"
let newLibrary = "/System/iOSSupport/usr/lib/swift/libswiftUIKit.dylib"
let libraryPadding = 8 - oldLibrary.utf8.count % 8
let libraryCommand = dylib_command(cmd: UInt32(LC_LOAD_DYLIB),
                                   cmdsize: UInt32(24 + oldLibrary.utf8.count + libraryPadding),
                                   dylib: dylib(name: lc_str(offset: 24), timestamp: 123,
                                                current_version: 42, compatibility_version: 7))
var withLibrary = executable([bytes(libraryCommand) + Data(oldLibrary.utf8) + Data(count: libraryPadding),
                              version()]) + Data([1, 2, 3, 4])
let originalLibrarySize = withLibrary.count
try Macho.replaceLibraries(&withLibrary)
try validate(withLibrary)
let replacedLibrary = withLibrary.extract(dylib_command.self, offset: 32)
let libraryPath = String(data: withLibrary, offset: 32, commandSize: Int(replacedLibrary.cmdsize),
                         loadCommandString: replacedLibrary.dylib.name)
check(libraryPath == newLibrary, "Dylib path was not replaced")
check(replacedLibrary.dylib.timestamp == 123, "Dylib metadata changed")
check(withLibrary.extract(load_command.self, offset: 32 + Int(replacedLibrary.cmdsize)).cmd
    == UInt32(LC_VERSION_MIN_IPHONEOS), "Following command was not preserved")
check(withLibrary.count == originalLibrarySize && withLibrary.suffix(4) == Data([1, 2, 3, 4]),
      "Dylib growth changed the file payload")

for padding in [Data(), Data(repeating: 1, count: 64)] {
    var binary = executable([version()], padding: 0) + padding
    let original = binary
    rejects("insufficient header padding") { try Macho.replaceVersionCommand(&binary) }
    check(binary == original, "Rejected rewrite mutated the binary")
}

// Section data can start with zeroes; it still must not be overwritten.
var section = section_64()
section.offset = UInt32(32 + MemoryLayout<segment_command_64>.size + MemoryLayout<section_64>.size + 16)
var segment = segment_command_64()
segment.cmd = UInt32(LC_SEGMENT_64)
segment.cmdsize = UInt32(MemoryLayout<segment_command_64>.size + MemoryLayout<section_64>.size)
segment.nsects = 1
var noPadding = executable([bytes(segment) + bytes(section), version()])
let noPaddingOriginal = noPadding
rejects("zero-filled section overlap") { try Macho.replaceVersionCommand(&noPadding) }
check(noPadding == noPaddingOriginal, "Rejected overlap changed payload")

// Exercise the actual file writer and ensure the executable permission survives.
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let file = directory.appendingPathComponent("executable")
try thin.write(to: file)
try FileManager.default.setAttributes([.posixPermissions: 0o751], ofItemAtPath: file.path)
try Macho.convertMacho(file)
try validate(Data(contentsOf: file))
let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
check((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o751, "Lost executable permissions")
try noPaddingOriginal.write(to: file)
rejects("failed conversion") { try Macho.convertMacho(file) }
let unchangedFile = try Data(contentsOf: file)
check(unchangedFile == noPaddingOriginal, "Failed conversion damaged the source file")

// Also parse and rewrite the real arm64 Mach-O emitted by the macOS 27 SDK.
let compiledBinary = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[0]))
try compiledBinary.write(to: file)
try Macho.convertMacho(file)
let catalyst = try Macho.isMachoValidArch(file)
check(catalyst, "The macOS 27 linked executable did not convert")

print("Mach-O regression checks passed")
