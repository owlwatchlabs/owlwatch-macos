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
