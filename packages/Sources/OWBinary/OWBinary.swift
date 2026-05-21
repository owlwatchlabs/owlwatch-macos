import Foundation

/// Parses Mach-O and Universal (fat) binaries.
///
/// `OWBinary` is a small read-only parser focused on the load-command surface
/// every later milestone needs:
///
/// - **Linked libraries.** `LC_LOAD_DYLIB`, `LC_LOAD_WEAK_DYLIB`,
///   `LC_REEXPORT_DYLIB`, `LC_LAZY_LOAD_DYLIB`, `LC_LOAD_UPWARD_DYLIB`,
///   `LC_ID_DYLIB`. Together these answer the M1.3-deferred question
///   "what dylibs does this process's binary link against?".
/// - **Runtime search paths.** `LC_RPATH`.
/// - **Identity.** `LC_UUID`.
/// - **Entry point.** `LC_MAIN`.
///
/// Everything else lands in `LoadCommand.other(rawType:)` with the raw
/// `cmd` value preserved so callers can switch on the constants from
/// `<mach-o/loader.h>` if they need finer-grained handling. Symbol tables
/// (`LC_SYMTAB`) and entropy / packing signals land in M2.2 / M2.3.
///
/// The parser is deliberately tolerant: malformed sections are reported via
/// `OWBinaryError` rather than crashing. Universal binaries are split into
/// their architecture-specific slices and each slice is parsed independently.
public enum OWBinary {
    /// Parses the file at `url`. Returns a `BinaryFile` describing one or
    /// more Mach-O slices (one for a thin binary, several for a Universal
    /// binary).
    ///
    /// - Parameter includeSymbols: when `true`, also parse each slice's
    ///   `LC_SYMTAB` symbol table and populate `Slice.symbols`. Defaults
    ///   to `false`: symbol tables can run into the hundreds of thousands
    ///   of entries on large binaries (Xcode, Chrome) and most callers
    ///   only want load-command data. When the slice has no `LC_SYMTAB`
    ///   (stripped binaries, some kernel extensions), `Slice.symbols` is
    ///   `[]` rather than `nil`.
    ///
    /// - Throws: `OWBinaryError` on read failure, unrecognized format, or
    ///   malformed header / load-command data.
    public static func parse(at url: URL, includeSymbols: Bool = false) throws -> BinaryFile {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw OWBinaryError.unreadable(url: url, underlying: error.localizedDescription)
        }
        return try data.withUnsafeBytes { rawBytes -> BinaryFile in
            var parser = Parser(bytes: rawBytes, url: url, includeSymbols: includeSymbols)
            return try parser.parseTopLevel()
        }
    }

    /// Computes Shannon entropy (bits per byte) of a contiguous byte range
    /// in a file. Range: 0.0 (every byte identical) to 8.0 (perfectly
    /// uniform distribution).
    ///
    /// Compiled native code typically scores 5.5–6.5; compressed or
    /// encrypted data scores above 7.5; pure ASCII text scores around
    /// 4.0–4.5. High-entropy `__TEXT,__text` sections are a strong
    /// packing / obfuscation signal.
    ///
    /// - Parameter url: Path to the file.
    /// - Parameter fileOffset: Byte offset within the file (note: for
    ///   Universal binaries this is offset within the *whole file*, not
    ///   within a particular slice. Callers iterating sections should
    ///   add the slice's base offset to `Section.fileOffset` themselves
    ///   when computing entropy on a single slice).
    /// - Parameter length: Number of bytes to consume.
    ///
    /// Returns 0.0 for length == 0 or any range outside the file.
    public static func entropy(of url: URL, fileOffset: UInt64, length: UInt64) throws -> Double {
        guard length > 0 else { return 0.0 }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw OWBinaryError.unreadable(url: url, underlying: error.localizedDescription)
        }
        let start = Int(fileOffset)
        let end = start &+ Int(length)
        guard start <= data.count, end <= data.count else {
            return 0.0
        }
        return data.withUnsafeBytes { rawBytes -> Double in
            let slice = rawBytes.bindMemory(to: UInt8.self)[start..<end]
            return shannonEntropy(of: slice)
        }
    }

    /// Computes entropy for every section in every slice of a parsed
    /// binary. Returns one `SectionEntropy` per section (across all slices)
    /// in the order they appear in the binary.
    ///
    /// Sections with zero `fileSize` (BSS-style uninitialized data) are
    /// skipped — their on-disk bytes don't exist to measure.
    public static func sectionEntropies(of binary: BinaryFile) throws -> [SectionEntropy] {
        let data: Data
        do {
            data = try Data(contentsOf: binary.url, options: [.mappedIfSafe])
        } catch {
            throw OWBinaryError.unreadable(url: binary.url, underlying: error.localizedDescription)
        }
        return data.withUnsafeBytes { rawBytes -> [SectionEntropy] in
            let bytes = rawBytes.bindMemory(to: UInt8.self)
            var result: [SectionEntropy] = []
            for (sliceIndex, slice) in binary.slices.enumerated() {
                // section.fileOffset is slice-relative; add the slice's base
                // to get the absolute file offset for reading.
                let sliceBase = Int(slice.fileOffsetInBinary)
                for command in slice.loadCommands {
                    guard case let .segment(segment) = command else { continue }
                    for section in segment.sections where !isZerofillSection(section) {
                        guard section.size > 0 else { continue }
                        let start = sliceBase + Int(section.fileOffset)
                        let end = start &+ Int(section.size)
                        guard start <= bytes.count, end <= bytes.count else { continue }
                        let entropy = shannonEntropy(of: bytes[start..<end])
                        result.append(SectionEntropy(
                            sliceIndex: sliceIndex,
                            segmentName: section.segmentName,
                            sectionName: section.name,
                            entropy: entropy,
                            size: section.size
                        ))
                    }
                }
            }
            return result
        }
    }
}

/// Section-type values that have no file backing (the bytes are
/// zero-initialized at load time, not read from the file). The bottom
/// 8 bits of `section.flags` carry the section type per `<mach-o/loader.h>`.
private func isZerofillSection(_ section: Section) -> Bool {
    let sectionType = section.flags & 0xFF
    // S_ZEROFILL = 0x1, S_GB_ZEROFILL = 0xC, S_THREAD_LOCAL_ZEROFILL = 0x12
    return sectionType == 0x1 || sectionType == 0xC || sectionType == 0x12
}

/// Shannon entropy over a byte sequence: H = -Σ p(x) log₂ p(x), where
/// p(x) is the frequency of byte value x in the range. Returns a value
/// in [0.0, 8.0]; 0.0 for empty input.
@usableFromInline
func shannonEntropy<Slice: Collection>(of bytes: Slice) -> Double where Slice.Element == UInt8 {
    var histogram = [Int](repeating: 0, count: 256)
    var total = 0
    for byte in bytes {
        histogram[Int(byte)] &+= 1
        total &+= 1
    }
    guard total > 0 else { return 0.0 }
    let invTotal = 1.0 / Double(total)
    var entropy = 0.0
    for count in histogram where count > 0 {
        let probability = Double(count) * invTotal
        entropy -= probability * (log2(probability))
    }
    return entropy
}

/// Errors produced by `OWBinary`.
public enum OWBinaryError: Error, Sendable, Equatable {
    /// The file at the given URL could not be read. `underlying` carries
    /// the OS-level error message (file not found, permission denied, etc.).
    case unreadable(url: URL, underlying: String)

    /// The file's leading bytes don't match any recognized magic number
    /// (`MH_MAGIC`/`MH_MAGIC_64`/`FAT_MAGIC`/`FAT_MAGIC_64` or their
    /// byte-swapped variants).
    case unrecognizedMagic(found: UInt32)

    /// The file claims to be a Mach-O / Universal binary but its declared
    /// sizes / offsets / counts don't fit within the file. `reason` is a
    /// short human-readable explanation.
    case malformed(reason: String)

    /// A read attempted to consume more bytes than remained in the file or
    /// in the current load-command region.
    case truncated(needed: Int, available: Int)
}
