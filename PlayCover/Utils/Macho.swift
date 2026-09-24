//
//  Macho.swift
//  PlayCover
//

import Foundation

class Macho {
    static func stripBinary(_ binary: inout Data) throws {
        guard binary.count >= MemoryLayout<fat_header>.size else {
            throw PlayCoverError.appCorrupted
        }
        var header = binary.extract(fat_header.self)
        var offset = MemoryLayout.size(ofValue: header)
        let shouldSwap = header.magic == FAT_CIGAM || header.magic == FAT_CIGAM_64
        let is64Bit = header.magic == FAT_MAGIC_64 || header.magic == FAT_CIGAM_64

        if header.magic == FAT_MAGIC || header.magic == FAT_CIGAM || is64Bit {
            // Make sure the endianness is correct
            if shouldSwap {
                swap_fat_header(&header, NXHostByteOrder())
            }

            let archSize = is64Bit ? MemoryLayout<fat_arch_64>.size : MemoryLayout<fat_arch>.size
            guard Int(header.nfat_arch) <= (binary.count - offset) / archSize else {
                throw PlayCoverError.appCorrupted
            }
            let tableEnd = offset + Int(header.nfat_arch) * archSize
            for _ in 0..<header.nfat_arch {
                let cpuType: cpu_type_t
                let sliceOffset: UInt64
                let sliceSize: UInt64
                if is64Bit {
                    var arch = binary.extract(fat_arch_64.self, offset: offset)
                    if shouldSwap { swap_fat_arch_64(&arch, 1, NXHostByteOrder()) }
                    (cpuType, sliceOffset, sliceSize) = (arch.cputype, arch.offset, arch.size)
                } else {
                    var arch = binary.extract(fat_arch.self, offset: offset)
                    if shouldSwap { swap_fat_arch(&arch, 1, NXHostByteOrder()) }
                    (cpuType, sliceOffset, sliceSize) = (arch.cputype, UInt64(arch.offset), UInt64(arch.size))
                }

                if cpuType == CPU_TYPE_ARM64 {
                    guard sliceOffset >= UInt64(tableEnd), sliceOffset <= UInt64(binary.count),
                          sliceSize >= UInt64(MemoryLayout<mach_header_64>.size),
                          sliceSize <= UInt64(binary.count) - sliceOffset else {
                        throw PlayCoverError.appCorrupted
                    }
                    print("Found ARM64 arch in fat binary")

                    binary = binary
                        .subdata(in: Int(sliceOffset)..<Int(sliceOffset + sliceSize))

                    return
                }

                offset += archSize
            }

            throw PlayCoverError.failedToStripBinary
        }
    }

    static func convertMacho(_ macho: URL) throws {
        print("Converting MachO at \(macho.path)")

        var binary = try Data(contentsOf: macho)

        print("Stripping MachO...")
        try stripBinary(&binary)
        print("Replacing version command...")
        try replaceVersionCommand(&binary)
        print("Replacing instances of @rpath dylibs...")
        try replaceLibraries(&binary)

        print("Writing revised MachO...")
        let attributes = try FileManager.default.attributesOfItem(atPath: macho.path)
        try binary.write(to: macho, options: .atomic)
        if let permissions = attributes[.posixPermissions] {
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: macho.path)
        }
    }

    static func replaceLibraries(_ binary: inout Data) throws {
        let dylibsToReplace = ["libswiftUIKit"]

        for dylib in dylibsToReplace {
            let rpathDylib = "@rpath/\(dylib).dylib"
            let libDylib = "/System/iOSSupport/usr/lib/swift/\(dylib).dylib"

            // 1. Check if dylib LC exists
            // 2. If it exists, take notes of its command type and dylib struct
            // 3. Replace existing LC with new dylib path

            try replaceLibrary(&binary, rpathDylib, libDylib)
        }
    }

    static func replaceLibrary(_ binary: inout Data, _ rpath: String, _ lib: String) throws {
        var dylibCommandType: UInt32 = 0
        var oldDylib: dylib?

        try replaceLastCommand(&binary, satisfy: {commandData, shouldSwap in
            // Perform steps 1-2
            let loadCommand = commandData.extract(load_command.self,
                                                  offset: commandData.startIndex,
                                                  swap: shouldSwap ? swap_load_command:nil)
            if ![LC_LOAD_WEAK_DYLIB, UInt32(LC_LOAD_DYLIB)].contains(loadCommand.cmd) {
                return false
            }
            let dylibCommand = commandData.extract(dylib_command.self,
                                                   offset: commandData.startIndex,
                                                   swap: shouldSwap ? swap_dylib_command:nil)
            if String(data: commandData,
                      offset: commandData.startIndex,
                      commandSize: Int(dylibCommand.cmdsize),
                      loadCommandString: dylibCommand.dylib.name) != rpath {
                return false
            }
            dylibCommandType = dylibCommand.cmd
            oldDylib = dylibCommand.dylib
            return true

        }, with: {shouldSwap in
            guard var newDylib = oldDylib else {
                // dylib with given rpath was not found in binary
                return nil
            }

            print("Found \(rpath) in binary")

            // Perform step 3
            let dylibCommandFixedSize = MemoryLayout<dylib_command>.size
            let stringLength = lib.lengthOfBytes(using: String.Encoding.utf8)
            // Align to 8 bytes, leave at least 1 zero for C-style string ending
            let padding = 8 - (stringLength % 8)
            let newDylibCommandSize = dylibCommandFixedSize + stringLength + padding

            newDylib.name = lc_str(offset: UInt32(dylibCommandFixedSize))
            var command = dylib_command(cmd: dylibCommandType,
                                        cmdsize: UInt32(newDylibCommandSize),
                                        dylib: newDylib)
            guard let stringData = lib.data(using: String.Encoding.utf8) else {
                print("Failed to replace dylib command: unrecognized character in target path")
                return nil
            }
            if shouldSwap {
                swap_dylib_command(&command, NX_BigEndian)
            }
            var commandData = Data(bytes: &command, count: dylibCommandFixedSize)
            commandData.append(stringData)
            commandData.append(Data(count: padding))
            return commandData
        }, atEnd: false)
    }

    static func replaceVersionCommand(_ binary: inout Data) throws {

        var macCatalystCommand = build_version_command(cmd: UInt32(LC_BUILD_VERSION),
                                                       cmdsize: 24,
                                                       platform: UInt32(PLATFORM_MACCATALYST),
                                                       minos: 0x000b0000,
                                                       sdk: 0x000e0000,
                                                       ntools: 0)

        try replaceLastCommand(&binary, satisfy: {data, shouldSwap in
            let loadCommand = data.extract(load_command.self,
                                           offset: data.startIndex,
                                           swap: shouldSwap ? swap_load_command:nil)
            return [UInt32(LC_VERSION_MIN_IPHONEOS),
                    UInt32(LC_VERSION_MIN_MACOSX),
                    UInt32(LC_BUILD_VERSION)]
                .contains(loadCommand.cmd)

        }, with: {shouldSwap in
            if shouldSwap {
                swap_build_version_command(&macCatalystCommand, NX_BigEndian)
            }
            return Data(bytes: &macCatalystCommand, count: MemoryLayout<build_version_command>.size)
        }, atEnd: true)
    }
}

extension Macho {
    static func replaceLastCommand(_ binary: inout Data,
                                   satisfy isTargetCommand: (Data, Bool) -> Bool,
                                   with getNewCommandData: (Bool) -> Data?,
                                   atEnd shouldAppend: Bool) throws {
        let headerSize = MemoryLayout<mach_header_64>.size
        guard binary.count >= headerSize else { throw PlayCoverError.appCorrupted }
        var header = binary.extract(mach_header_64.self)
        let shouldSwap = header.magic == MH_CIGAM_64
        if shouldSwap { swap_mach_header_64(&header, NXHostByteOrder()) }

        var oldCommandStart = headerSize
        var oldCommandSize: UInt32 = 0
        var firstFileContent = binary.count

        let movedCommandsEnd = try iterateLoadCommands(binary: binary) { offset, needSwap in
            let loadCommand = binary.extract(load_command.self,
                                             offset: offset,
                                             swap: needSwap ? swap_load_command:nil)
            if isTargetCommand(binary[offset ..< offset+Int(loadCommand.cmdsize)], needSwap) {
                oldCommandStart = offset
                oldCommandSize = loadCommand.cmdsize
            }
            firstFileContent = min(firstFileContent,
                                   fileContentOffset(binary, at: offset, command: loadCommand, shouldSwap: needSwap))
            return false
        }

        let oldCommandEnd = oldCommandStart + Int(oldCommandSize)
        guard let newCommandData = getNewCommandData(shouldSwap) else {
            return
        }
        let newCommandSize = UInt32(newCommandData.count)

        var resultingCommandsData = binary[oldCommandEnd..<movedCommandsEnd]
        if shouldAppend {
            resultingCommandsData.append(newCommandData)
        } else {
            resultingCommandsData.insert(contentsOf: newCommandData,
                                         at: resultingCommandsData.startIndex)
        }

        let injectionEnd = movedCommandsEnd - Int(oldCommandSize) + Int(newCommandSize)
        if injectionEnd > movedCommandsEnd {
            guard injectionEnd <= firstFileContent,
                  binary[movedCommandsEnd..<injectionEnd].allSatisfy({ $0 == 0 }) else {
                // Refuse to overwrite sections, including payload bytes that happen to be zero.
                throw PlayCoverError.appCorrupted
            }
        } else {
            binary.replaceSubrange(injectionEnd ..< movedCommandsEnd,
                                   with: Data(count: movedCommandsEnd - injectionEnd))
        }
        binary.replaceSubrange(oldCommandStart..<injectionEnd, with: resultingCommandsData)

        // Write new header data
        header.sizeofcmds -= oldCommandSize
        header.sizeofcmds += newCommandSize
        if oldCommandSize == 0 { header.ncmds += 1 }
        if shouldSwap { swap_mach_header_64(&header, NX_BigEndian) }
        let newHeaderData = Data(bytes: &header, count: headerSize)
        binary.replaceSubrange(0..<headerSize, with: newHeaderData)
    }

    static func iterateLoadCommands(binary: Data, _ evaluate: (Int, Bool) -> Bool) throws -> Int {
        let headerSize = MemoryLayout<mach_header_64>.size
        guard binary.count >= headerSize else { throw PlayCoverError.appCorrupted }
        var header = binary.extract(mach_header_64.self)
        guard header.magic == MH_MAGIC_64 || header.magic == MH_CIGAM_64 else {
            throw PlayCoverError.appCorrupted
        }
        var offset = headerSize
        let shouldSwap = header.magic == MH_CIGAM_64
        if  shouldSwap {
            swap_mach_header_64(&header, NXHostByteOrder())
            print("Slim Mach-O has reversed byte order")
        }

        let allCommandsEnd = headerSize + Int(header.sizeofcmds)
        if allCommandsEnd > binary.count || allCommandsEnd <= headerSize {
            print("Cannot iterate load commands: Mach-O file is corrupted(-1)")
            throw PlayCoverError.appCorrupted
        }
        for index in 0..<header.ncmds {
            guard offset <= allCommandsEnd - MemoryLayout<load_command>.size else {
                throw PlayCoverError.appCorrupted
            }
            let loadCommand = binary.extract(load_command.self,
                                             offset: offset,
                                             swap: shouldSwap ? swap_load_command:nil)
            let commandEnd = offset + Int(loadCommand.cmdsize)
            if commandEnd > allCommandsEnd || loadCommand.cmdsize < MemoryLayout<load_command>.size
                || loadCommand.cmdsize % 8 != 0 {
                print("Cannot iterate load commands: Mach-O file is corrupted(\(index))")
                throw PlayCoverError.appCorrupted
            }
            try validateCommand(binary, at: offset, command: loadCommand, shouldSwap: shouldSwap)
            let terminated = evaluate(offset, shouldSwap)
            offset = commandEnd
            if terminated {
                return offset
            }
        }
        guard offset == allCommandsEnd else { throw PlayCoverError.appCorrupted }
        return offset
    }

    static func isMachoEncrypted(atURL url: URL) throws -> Bool {
        var binary = try Data(contentsOf: url)
        try stripBinary(&binary)
        var result = false
        _ = try iterateLoadCommands(binary: binary) { offset, shouldSwap in
            let loadCommand = binary.extract(load_command.self,
                                             offset: offset,
                                             swap: shouldSwap ? swap_load_command:nil)
            if loadCommand.cmd == UInt32(LC_ENCRYPTION_INFO_64) {
                let infoCommand = binary.extract(encryption_info_command_64.self,
                                                 offset: offset,
                                                 swap: shouldSwap ? swap_encryption_command_64:nil)
                result = infoCommand.cryptid != 0
                return true
            }
            return false
        }
        return result
    }

    static func isMachoValidArch(_ url: URL) throws -> Bool {
        var binary = try Data(contentsOf: url)
        try stripBinary(&binary)
        var result = false
        _ = try iterateLoadCommands(binary: binary) { offset, shouldSwap in
            let loadCommand = binary.extract(load_command.self,
                                             offset: offset,
                                             swap: shouldSwap ? swap_load_command:nil)
            if loadCommand.cmd == UInt32(LC_BUILD_VERSION) {
                let versionCommand = binary.extract(build_version_command.self,
                                                    offset: offset,
                                                    swap: shouldSwap ? swap_build_version_command:nil)
                result = versionCommand.platform == PLATFORM_MACCATALYST
                return true
            }
            return false
        }
        return result
    }
}

private extension Macho {
    static func fileContentOffset(_ binary: Data, at offset: Int,
                                  command: load_command, shouldSwap: Bool) -> Int {
        guard command.cmd == UInt32(LC_SEGMENT_64) else { return binary.count }
        let segment = binary.extract(segment_command_64.self, offset: offset,
                                     swap: shouldSwap ? swap_segment_command_64:nil)
        var firstFileContent = binary.count
        if segment.fileoff > 0 {
            firstFileContent = Int(min(UInt64(firstFileContent), segment.fileoff))
        }
        for index in 0..<Int(segment.nsects) {
            let sectionOffset = offset + MemoryLayout<segment_command_64>.size
                + index * MemoryLayout<section_64>.size
            var section = binary.extract(section_64.self, offset: sectionOffset)
            if shouldSwap { swap_section_64(&section, 1, NXHostByteOrder()) }
            if section.offset > 0 {
                firstFileContent = min(firstFileContent, Int(section.offset))
            }
        }
        return firstFileContent
    }

    static func validateCommand(_ binary: Data, at offset: Int,
                                command: load_command, shouldSwap: Bool) throws {
        let size = Int(command.cmdsize)
        switch command.cmd {
        case UInt32(LC_SEGMENT_64):
            try validateSegment(binary, at: offset, size: size, shouldSwap: shouldSwap)
        case UInt32(LC_LOAD_DYLIB), LC_LOAD_WEAK_DYLIB:
            try validateDylib(binary, at: offset, size: size, shouldSwap: shouldSwap)
        case UInt32(LC_ENCRYPTION_INFO_64):
            guard size >= MemoryLayout<encryption_info_command_64>.size else { throw PlayCoverError.appCorrupted }
        case UInt32(LC_BUILD_VERSION):
            try validateBuildVersion(binary, at: offset, size: size, shouldSwap: shouldSwap)
        case UInt32(LC_VERSION_MIN_IPHONEOS), UInt32(LC_VERSION_MIN_MACOSX):
            guard size >= MemoryLayout<version_min_command>.size else { throw PlayCoverError.appCorrupted }
        default:
            break
        }
    }

    static func validateSegment(_ binary: Data, at offset: Int, size: Int, shouldSwap: Bool) throws {
        guard size >= MemoryLayout<segment_command_64>.size else { throw PlayCoverError.appCorrupted }
        let segment = binary.extract(segment_command_64.self, offset: offset,
                                     swap: shouldSwap ? swap_segment_command_64:nil)
        guard Int(segment.nsects) <= (size - MemoryLayout<segment_command_64>.size)
            / MemoryLayout<section_64>.size else { throw PlayCoverError.appCorrupted }
    }

    static func validateDylib(_ binary: Data, at offset: Int, size: Int, shouldSwap: Bool) throws {
        guard size >= MemoryLayout<dylib_command>.size else { throw PlayCoverError.appCorrupted }
        let dylib = binary.extract(dylib_command.self, offset: offset,
                                   swap: shouldSwap ? swap_dylib_command:nil)
        let nameOffset = Int(dylib.dylib.name.offset)
        guard nameOffset >= MemoryLayout<dylib_command>.size, nameOffset < size,
              binary[(offset + nameOffset)..<(offset + size)].contains(0) else {
            throw PlayCoverError.appCorrupted
        }
    }

    static func validateBuildVersion(_ binary: Data, at offset: Int, size: Int, shouldSwap: Bool) throws {
        guard size >= MemoryLayout<build_version_command>.size else { throw PlayCoverError.appCorrupted }
        let version = binary.extract(build_version_command.self, offset: offset,
                                     swap: shouldSwap ? swap_build_version_command:nil)
        guard Int(version.ntools) <= (size - MemoryLayout<build_version_command>.size)
            / MemoryLayout<build_tool_version>.size else { throw PlayCoverError.appCorrupted }
    }
}
