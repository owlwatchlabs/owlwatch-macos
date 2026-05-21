import Foundation

// MARK: - Mach-O magic numbers (from <mach-o/loader.h>)

private let machOMagic32: UInt32 = 0xFEED_FACE
private let machOMagic32Swapped: UInt32 = 0xCEFA_EDFE
private let machOMagic64: UInt32 = 0xFEED_FACF
private let machOMagic64Swapped: UInt32 = 0xCFFA_EDFE
private let fatMagic: UInt32 = 0xCAFE_BABE
private let fatMagicSwapped: UInt32 = 0xBEBA_FECA
private let fatMagic64: UInt32 = 0xCAFE_BABF
private let fatMagic64Swapped: UInt32 = 0xBFBA_FECA

// MARK: - Load command constants (subset of <mach-o/loader.h>)

private let lcLoadDylib: UInt32 = 0x0000_000C
private let lcIDDylib: UInt32 = 0x0000_000D
private let lcLoadWeakDylib: UInt32 = 0x8000_0018
private let lcReexportDylib: UInt32 = 0x8000_001F
private let lcLazyLoadDylib: UInt32 = 0x0000_0020
private let lcLoadUpwardDylib: UInt32 = 0x8000_0023
private let lcRPath: UInt32 = 0x8000_001C
private let lcUUID: UInt32 = 0x0000_001B
private let lcMain: UInt32 = 0x8000_0028

private let dylibCommandKinds: Set<UInt32> = [
    lcLoadDylib, lcIDDylib, lcLoadWeakDylib, lcReexportDylib, lcLazyLoadDylib, lcLoadUpwardDylib
]

// MARK: - Parser

/// Top-level parser. One instance per file; not reusable across files.
struct Parser {
    let bytes: UnsafeRawBufferPointer
    let url: URL

    mutating func parseTopLevel() throws -> BinaryFile {
        guard bytes.count >= 4 else {
            throw OWBinaryError.truncated(needed: 4, available: bytes.count)
        }
        let magic: UInt32 = readUInt32(at: 0, littleEndian: true)

        switch magic {
        case fatMagic, fatMagicSwapped, fatMagic64, fatMagic64Swapped:
            // Universal headers are conventionally big-endian regardless of host.
            return try parseUniversal()
        case machOMagic32, machOMagic32Swapped, machOMagic64, machOMagic64Swapped:
            let slice = try parseMachOSlice(at: 0, size: bytes.count)
            return BinaryFile(url: url, isUniversal: false, slices: [slice])
        default:
            throw OWBinaryError.unrecognizedMagic(found: magic)
        }
    }

    // MARK: Universal (fat)

    private mutating func parseUniversal() throws -> BinaryFile {
        let magic = readUInt32(at: 0, littleEndian: true)
        let is64Bit = (magic == fatMagic64 || magic == fatMagic64Swapped)
        // Fat headers are big-endian on disk; on a little-endian host we
        // need to byte-swap the 32-bit fields ourselves.
        let nfat = readUInt32(at: 4, littleEndian: false)

        let archEntrySize = is64Bit ? 32 : 20
        let totalArchSize = Int(nfat) * archEntrySize
        guard 8 + totalArchSize <= bytes.count else {
            throw OWBinaryError.truncated(needed: 8 + totalArchSize, available: bytes.count)
        }

        var slices: [Slice] = []
        for index in 0..<Int(nfat) {
            let archOffset = 8 + index * archEntrySize
            let (sliceOffset, sliceSize) = try readFatArch(at: archOffset, is64Bit: is64Bit)
            guard sliceOffset + sliceSize <= bytes.count else {
                throw OWBinaryError.malformed(
                    reason: "fat arch \(index) extends past end of file"
                )
            }
            slices.append(try parseMachOSlice(at: sliceOffset, size: sliceSize))
        }
        return BinaryFile(url: url, isUniversal: true, slices: slices)
    }

    private func readFatArch(at offset: Int, is64Bit: Bool) throws -> (offset: Int, size: Int) {
        if is64Bit {
            // fat_arch_64: cputype(4) cpusubtype(4) offset(8) size(8) align(4) reserved(4)
            let archOffset = readUInt64(at: offset + 8, littleEndian: false)
            let archSize = readUInt64(at: offset + 16, littleEndian: false)
            return (Int(archOffset), Int(archSize))
        } else {
            // fat_arch: cputype(4) cpusubtype(4) offset(4) size(4) align(4)
            let archOffset = readUInt32(at: offset + 8, littleEndian: false)
            let archSize = readUInt32(at: offset + 12, littleEndian: false)
            return (Int(archOffset), Int(archSize))
        }
    }

    // MARK: Mach-O slice (thin)

    private func parseMachOSlice(at base: Int, size: Int) throws -> Slice {
        guard base + 28 <= bytes.count else {
            throw OWBinaryError.truncated(needed: base + 28, available: bytes.count)
        }
        let magic = readUInt32(at: base, littleEndian: true)
        let (is64Bit, isLittleEndian) = try classifyMachOMagic(magic)
        let headerSize = is64Bit ? 32 : 28

        guard base + headerSize <= bytes.count, headerSize <= size else {
            throw OWBinaryError.truncated(needed: base + headerSize, available: bytes.count)
        }

        let cpuType = Int32(bitPattern: readUInt32(at: base + 4, littleEndian: isLittleEndian))
        let fileTypeRaw = readUInt32(at: base + 12, littleEndian: isLittleEndian)
        let ncmds = readUInt32(at: base + 16, littleEndian: isLittleEndian)
        let sizeofcmds = readUInt32(at: base + 20, littleEndian: isLittleEndian)
        let flags = readUInt32(at: base + 24, littleEndian: isLittleEndian)

        let architecture = Architecture(rawCPUType: cpuType)
        let fileType = FileType(rawType: fileTypeRaw)

        // Load commands begin immediately after the header.
        let lcStart = base + headerSize
        let lcEnd = lcStart + Int(sizeofcmds)
        guard lcEnd <= bytes.count, lcStart + Int(sizeofcmds) <= base + size else {
            throw OWBinaryError.malformed(
                reason: "load-command region overruns slice (slice base=\(base) size=\(size))"
            )
        }

        let loadCommands = try parseLoadCommands(
            start: lcStart,
            end: lcEnd,
            count: Int(ncmds),
            littleEndian: isLittleEndian
        )

        return Slice(
            architecture: architecture,
            fileType: fileType,
            flags: flags,
            loadCommands: loadCommands
        )
    }

    private func classifyMachOMagic(_ magic: UInt32) throws -> (is64Bit: Bool, littleEndian: Bool) {
        switch magic {
        case machOMagic32: return (false, true)
        case machOMagic32Swapped: return (false, false)
        case machOMagic64: return (true, true)
        case machOMagic64Swapped: return (true, false)
        default:
            throw OWBinaryError.unrecognizedMagic(found: magic)
        }
    }

    // MARK: Load commands

    private func parseLoadCommands(
        start: Int,
        end: Int,
        count: Int,
        littleEndian: Bool
    ) throws -> [LoadCommand] {
        var cursor = start
        var result: [LoadCommand] = []
        result.reserveCapacity(count)

        for index in 0..<count {
            guard cursor + 8 <= end else {
                throw OWBinaryError.malformed(
                    reason: "load-command \(index) header runs past load-command region"
                )
            }
            let cmd = readUInt32(at: cursor, littleEndian: littleEndian)
            let cmdsize = readUInt32(at: cursor + 4, littleEndian: littleEndian)
            guard cmdsize >= 8, cursor + Int(cmdsize) <= end else {
                throw OWBinaryError.malformed(
                    reason: "load-command \(index) cmdsize=\(cmdsize) out of bounds"
                )
            }

            result.append(parseSingleLoadCommand(
                cmd: cmd,
                start: cursor,
                size: Int(cmdsize),
                littleEndian: littleEndian
            ))
            cursor += Int(cmdsize)
        }
        return result
    }

    private func parseSingleLoadCommand(
        cmd: UInt32,
        start: Int,
        size: Int,
        littleEndian: Bool
    ) -> LoadCommand {
        if dylibCommandKinds.contains(cmd) {
            return parseDylibCommand(cmd: cmd, start: start, size: size, littleEndian: littleEndian)
        }
        switch cmd {
        case lcRPath:
            return parseRPathCommand(start: start, size: size, littleEndian: littleEndian)
        case lcUUID:
            return parseUUIDCommand(start: start, size: size)
        case lcMain:
            return parseMainCommand(start: start, size: size, littleEndian: littleEndian)
        default:
            return .other(rawType: cmd)
        }
    }

    private func parseDylibCommand(
        cmd: UInt32,
        start: Int,
        size: Int,
        littleEndian: Bool
    ) -> LoadCommand {
        // dylib_command layout:
        //   uint32 cmd, uint32 cmdsize,
        //   uint32 name.offset, uint32 timestamp,
        //   uint32 current_version, uint32 compatibility_version,
        //   followed by the null-terminated name string padded to 8 bytes.
        guard size >= 24 else { return .other(rawType: cmd) }
        let nameOffset = Int(readUInt32(at: start + 8, littleEndian: littleEndian))
        let timestamp = readUInt32(at: start + 12, littleEndian: littleEndian)
        let currentVersion = readUInt32(at: start + 16, littleEndian: littleEndian)
        let compatVersion = readUInt32(at: start + 20, littleEndian: littleEndian)

        let nameStart = start + nameOffset
        let nameLimit = start + size
        guard nameOffset >= 24, nameStart <= nameLimit else { return .other(rawType: cmd) }

        let name = readNullTerminatedString(start: nameStart, limit: nameLimit)
        return .dylib(LoadCommand.Dylib(
            rawCommand: cmd,
            name: name,
            timestamp: timestamp,
            currentVersion: currentVersion,
            compatibilityVersion: compatVersion
        ))
    }

    private func parseRPathCommand(
        start: Int,
        size: Int,
        littleEndian: Bool
    ) -> LoadCommand {
        // rpath_command: uint32 cmd, uint32 cmdsize, uint32 path.offset, then string.
        guard size >= 12 else { return .other(rawType: lcRPath) }
        let pathOffset = Int(readUInt32(at: start + 8, littleEndian: littleEndian))
        let pathStart = start + pathOffset
        let pathLimit = start + size
        guard pathOffset >= 12, pathStart <= pathLimit else { return .other(rawType: lcRPath) }
        let path = readNullTerminatedString(start: pathStart, limit: pathLimit)
        return .rpath(path: path)
    }

    private func parseUUIDCommand(start: Int, size: Int) -> LoadCommand {
        // uuid_command: uint32 cmd, uint32 cmdsize, uint8 uuid[16].
        guard size >= 24 else { return .other(rawType: lcUUID) }
        var bytesArray = [UInt8](repeating: 0, count: 16)
        for index in 0..<16 {
            bytesArray[index] = bytes[start + 8 + index]
        }
        let uuid = UUID(uuid: (
            bytesArray[0], bytesArray[1], bytesArray[2], bytesArray[3],
            bytesArray[4], bytesArray[5], bytesArray[6], bytesArray[7],
            bytesArray[8], bytesArray[9], bytesArray[10], bytesArray[11],
            bytesArray[12], bytesArray[13], bytesArray[14], bytesArray[15]
        ))
        return .uuid(uuid)
    }

    private func parseMainCommand(
        start: Int,
        size: Int,
        littleEndian: Bool
    ) -> LoadCommand {
        // entry_point_command: uint32 cmd, uint32 cmdsize, uint64 entryoff, uint64 stacksize.
        guard size >= 24 else { return .other(rawType: lcMain) }
        let entryOffset = readUInt64(at: start + 8, littleEndian: littleEndian)
        let stackSize = readUInt64(at: start + 16, littleEndian: littleEndian)
        return .main(entryOffset: entryOffset, stackSize: stackSize)
    }

    // MARK: Byte readers

    private func readUInt32(at offset: Int, littleEndian: Bool) -> UInt32 {
        // `bytes.load(fromByteOffset:as:)` reads a UInt32 in native byte order.
        // The host (macOS arm64/x86_64) is little-endian; if the file is
        // little-endian too, the value is correct as loaded. If the file is
        // big-endian, byte-swap to recover the logical value.
        let raw = bytes.load(fromByteOffset: offset, as: UInt32.self)
        return littleEndian ? raw : raw.byteSwapped
    }

    private func readUInt64(at offset: Int, littleEndian: Bool) -> UInt64 {
        let raw = bytes.load(fromByteOffset: offset, as: UInt64.self)
        return littleEndian ? raw : raw.byteSwapped
    }

    private func readNullTerminatedString(start: Int, limit: Int) -> String {
        var end = start
        while end < limit, bytes[end] != 0 {
            end += 1
        }
        let slice = bytes[start..<end]
        let array = Array(slice)
        return String(bytes: array, encoding: .utf8) ?? ""
    }
}
