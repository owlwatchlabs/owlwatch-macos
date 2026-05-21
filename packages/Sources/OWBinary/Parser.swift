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
private let lcSymtab: UInt32 = 0x0000_0002
private let lcSegment: UInt32 = 0x0000_0001
private let lcSegment64: UInt32 = 0x0000_0019

// MARK: - nlist n_type bitfield (from <mach-o/nlist.h>)

private let nStab: UInt8 = 0xE0   // debugging entry — bits 5..7 set
private let nPExt: UInt8 = 0x10   // private external
private let nType: UInt8 = 0x0E   // type-field mask
private let nExt: UInt8 = 0x01    // external

private let nUndef: UInt8 = 0x00
private let nAbsolute: UInt8 = 0x02
private let nIndirect: UInt8 = 0x0A
private let nPrebound: UInt8 = 0x0C
private let nSection: UInt8 = 0x0E

private let dylibCommandKinds: Set<UInt32> = [
    lcLoadDylib, lcIDDylib, lcLoadWeakDylib, lcReexportDylib, lcLazyLoadDylib, lcLoadUpwardDylib
]

// MARK: - Parser

/// Top-level parser. One instance per file; not reusable across files.
struct Parser {
    let bytes: UnsafeRawBufferPointer
    let url: URL
    let includeSymbols: Bool

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

        let (loadCommands, symtabInfo) = try parseLoadCommands(
            start: lcStart,
            end: lcEnd,
            count: Int(ncmds),
            littleEndian: isLittleEndian
        )

        let symbols: [Symbol]?
        if includeSymbols {
            if let info = symtabInfo {
                symbols = try parseSymbols(
                    sliceBase: base,
                    sliceSize: size,
                    symtab: info,
                    is64Bit: is64Bit,
                    littleEndian: isLittleEndian
                )
            } else {
                // includeSymbols requested but no LC_SYMTAB in this slice
                // (stripped binary, kernel extension, etc.). Empty array
                // distinguishes "requested but unavailable" from "not requested".
                symbols = []
            }
        } else {
            symbols = nil
        }

        return Slice(
            architecture: architecture,
            fileType: fileType,
            flags: flags,
            fileOffsetInBinary: UInt64(base),
            loadCommands: loadCommands,
            symbols: symbols
        )
    }

    /// Compact record of an `LC_SYMTAB` load command's four offset/size fields.
    /// Captured during load-command iteration so the slice parser can read the
    /// actual symbol table after the iteration completes.
    private struct SymtabInfo {
        let symoff: UInt32
        let nsyms: UInt32
        let stroff: UInt32
        let strsize: UInt32
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
    ) throws -> (commands: [LoadCommand], symtab: SymtabInfo?) {
        var cursor = start
        var result: [LoadCommand] = []
        var symtab: SymtabInfo? = nil
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

            // LC_SYMTAB is captured for later symbol-table parsing but doesn't
            // get a dedicated LoadCommand variant — the actual symbols are
            // exposed via `Slice.symbols` instead.
            if cmd == lcSymtab, Int(cmdsize) >= 24, symtab == nil {
                symtab = SymtabInfo(
                    symoff: readUInt32(at: cursor + 8, littleEndian: littleEndian),
                    nsyms: readUInt32(at: cursor + 12, littleEndian: littleEndian),
                    stroff: readUInt32(at: cursor + 16, littleEndian: littleEndian),
                    strsize: readUInt32(at: cursor + 20, littleEndian: littleEndian)
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
        return (result, symtab)
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
        case lcSegment64:
            return parseSegmentCommand(start: start, size: size, is64Bit: true, littleEndian: littleEndian)
        case lcSegment:
            return parseSegmentCommand(start: start, size: size, is64Bit: false, littleEndian: littleEndian)
        default:
            return .other(rawType: cmd)
        }
    }

    private func parseSegmentCommand(
        start: Int,
        size: Int,
        is64Bit: Bool,
        littleEndian: Bool
    ) -> LoadCommand {
        // Header layout (after cmd+cmdsize):
        //   char segname[16]
        //   uint{32,64} vmaddr, vmsize, fileoff, filesize
        //   int32 maxprot, int32 initprot
        //   uint32 nsects, uint32 flags
        let headerEnd: Int
        let segnameOffset = start + 8
        let addressOffset = start + 8 + 16  // skip cmd(4) + cmdsize(4) + segname(16)

        if is64Bit {
            headerEnd = addressOffset + 8 + 8 + 8 + 8 + 4 + 4 + 4 + 4  // = 72 total
        } else {
            headerEnd = addressOffset + 4 + 4 + 4 + 4 + 4 + 4 + 4 + 4  // = 56 total
        }
        guard size >= (headerEnd - start) else {
            return .other(rawType: is64Bit ? lcSegment64 : lcSegment)
        }

        let segmentName = readFixedString(start: segnameOffset, length: 16)
        let vmAddress: UInt64
        let vmSize: UInt64
        let fileOffset: UInt64
        let fileSize: UInt64
        let cursor: Int
        if is64Bit {
            vmAddress = readUInt64(at: addressOffset, littleEndian: littleEndian)
            vmSize = readUInt64(at: addressOffset + 8, littleEndian: littleEndian)
            fileOffset = readUInt64(at: addressOffset + 16, littleEndian: littleEndian)
            fileSize = readUInt64(at: addressOffset + 24, littleEndian: littleEndian)
            cursor = addressOffset + 32
        } else {
            vmAddress = UInt64(readUInt32(at: addressOffset, littleEndian: littleEndian))
            vmSize = UInt64(readUInt32(at: addressOffset + 4, littleEndian: littleEndian))
            fileOffset = UInt64(readUInt32(at: addressOffset + 8, littleEndian: littleEndian))
            fileSize = UInt64(readUInt32(at: addressOffset + 12, littleEndian: littleEndian))
            cursor = addressOffset + 16
        }
        let maxProt = Int32(bitPattern: readUInt32(at: cursor, littleEndian: littleEndian))
        let initProt = Int32(bitPattern: readUInt32(at: cursor + 4, littleEndian: littleEndian))
        let nsects = readUInt32(at: cursor + 8, littleEndian: littleEndian)
        let flags = readUInt32(at: cursor + 12, littleEndian: littleEndian)

        // Sections immediately follow the segment header.
        let sectionStart = is64Bit ? cursor + 16 : cursor + 16
        let sectionStride = is64Bit ? 80 : 68  // sizeof(section_64) vs sizeof(section)
        var sections: [Section] = []
        sections.reserveCapacity(Int(nsects))
        for index in 0..<Int(nsects) {
            let secOffset = sectionStart + index * sectionStride
            guard secOffset + sectionStride <= start + size else { break }
            sections.append(parseSection(
                at: secOffset,
                is64Bit: is64Bit,
                littleEndian: littleEndian
            ))
        }

        return .segment(Segment(
            name: segmentName,
            vmAddress: vmAddress,
            vmSize: vmSize,
            fileOffset: fileOffset,
            fileSize: fileSize,
            maxProtection: SegmentProtection(rawValue: maxProt),
            initialProtection: SegmentProtection(rawValue: initProt),
            flags: flags,
            sections: sections
        ))
    }

    private func parseSection(at start: Int, is64Bit: Bool, littleEndian: Bool) -> Section {
        // section / section_64 layout:
        //   char sectname[16]
        //   char segname[16]
        //   uint{32,64} addr, size
        //   uint32 offset, align, reloff, nreloc, flags, reserved1, reserved2
        //   (section_64 adds reserved3)
        let sectName = readFixedString(start: start, length: 16)
        let segName = readFixedString(start: start + 16, length: 16)
        let address: UInt64
        let size: UInt64
        let metadataOffset: Int
        if is64Bit {
            address = readUInt64(at: start + 32, littleEndian: littleEndian)
            size = readUInt64(at: start + 40, littleEndian: littleEndian)
            metadataOffset = start + 48
        } else {
            address = UInt64(readUInt32(at: start + 32, littleEndian: littleEndian))
            size = UInt64(readUInt32(at: start + 36, littleEndian: littleEndian))
            metadataOffset = start + 40
        }
        let fileOffset = readUInt32(at: metadataOffset, littleEndian: littleEndian)
        // skip align(4) reloff(4) nreloc(4) → flags is at metadataOffset+16
        let flags = readUInt32(at: metadataOffset + 16, littleEndian: littleEndian)

        return Section(
            name: sectName,
            segmentName: segName,
            address: address,
            size: size,
            fileOffset: fileOffset,
            flags: flags
        )
    }

    private func readFixedString(start: Int, length: Int) -> String {
        // Section / segment names in Mach-O are fixed-length char arrays
        // padded with NULs. Read up to the first NUL (or the full length).
        var end = start
        let limit = start + length
        while end < limit, bytes[end] != 0 {
            end += 1
        }
        let array: [UInt8] = (start..<end).map { bytes[$0] }
        return String(bytes: array, encoding: .utf8) ?? ""
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

    // MARK: Symbol table (LC_SYMTAB → nlist[/_64] + string table)

    private func parseSymbols(
        sliceBase: Int,
        sliceSize: Int,
        symtab: SymtabInfo,
        is64Bit: Bool,
        littleEndian: Bool
    ) throws -> [Symbol] {
        // symoff and stroff in LC_SYMTAB are file offsets RELATIVE TO THE
        // START OF THE SLICE, not the start of the Universal binary.
        let entryStride = is64Bit ? 16 : 12  // sizeof(nlist_64) vs sizeof(nlist)
        let symStart = sliceBase + Int(symtab.symoff)
        let symEnd = symStart + Int(symtab.nsyms) * entryStride
        let strStart = sliceBase + Int(symtab.stroff)
        let strEnd = strStart + Int(symtab.strsize)

        guard symEnd <= sliceBase + sliceSize, strEnd <= sliceBase + sliceSize,
              symEnd <= bytes.count, strEnd <= bytes.count else {
            throw OWBinaryError.malformed(
                reason: "LC_SYMTAB symoff+nsyms or stroff+strsize extends past slice"
            )
        }

        var result: [Symbol] = []
        result.reserveCapacity(Int(symtab.nsyms))
        for index in 0..<Int(symtab.nsyms) {
            let entryOffset = symStart + index * entryStride
            let nstrx = readUInt32(at: entryOffset, littleEndian: littleEndian)
            let typeByte = bytes[entryOffset + 4]
            let sectionIndex = bytes[entryOffset + 5]
            let descriptionBits: UInt16
            let value: UInt64
            if is64Bit {
                descriptionBits = readUInt16(at: entryOffset + 6, littleEndian: littleEndian)
                value = readUInt64(at: entryOffset + 8, littleEndian: littleEndian)
            } else {
                // 32-bit nlist: n_desc is int16, n_value is uint32.
                descriptionBits = readUInt16(at: entryOffset + 6, littleEndian: littleEndian)
                value = UInt64(readUInt32(at: entryOffset + 8, littleEndian: littleEndian))
            }

            let name = readSymbolName(strStart: strStart, strEnd: strEnd, offset: Int(nstrx))
            let kind = classifySymbol(typeByte: typeByte)
            let isExternal = (typeByte & nExt) != 0
            let isPrivateExternal = (typeByte & nPExt) != 0

            result.append(Symbol(
                name: name,
                kind: kind,
                value: value,
                isExternal: isExternal,
                isPrivateExternal: isPrivateExternal,
                sectionIndex: sectionIndex,
                descriptionBits: descriptionBits
            ))
        }
        return result
    }

    private func classifySymbol(typeByte: UInt8) -> Symbol.Kind {
        if (typeByte & nStab) != 0 {
            return .stab(rawType: typeByte)
        }
        switch typeByte & nType {
        case nUndef: return .undefined
        case nAbsolute: return .absolute
        case nSection: return .defined
        case nPrebound: return .prebound
        case nIndirect: return .indirect
        default: return .undefined
        }
    }

    private func readSymbolName(strStart: Int, strEnd: Int, offset: Int) -> String {
        guard offset >= 0, strStart + offset < strEnd else { return "" }
        let nameStart = strStart + offset
        return readNullTerminatedString(start: nameStart, limit: strEnd)
    }

    // MARK: Byte readers

    private func readUInt16(at offset: Int, littleEndian: Bool) -> UInt16 {
        let raw = bytes.load(fromByteOffset: offset, as: UInt16.self)
        return littleEndian ? raw : raw.byteSwapped
    }

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
