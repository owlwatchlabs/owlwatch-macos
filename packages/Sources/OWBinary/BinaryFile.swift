import Foundation

/// Top-level result of parsing a file.
///
/// A thin Mach-O has exactly one slice; a Universal (fat) binary has one
/// slice per architecture (typically `[x86_64, arm64]` on modern macOS).
public struct BinaryFile: Sendable, Equatable, Hashable {
    public let url: URL
    public let isUniversal: Bool
    public let slices: [Slice]

    public init(url: URL, isUniversal: Bool, slices: [Slice]) {
        self.url = url
        self.isUniversal = isUniversal
        self.slices = slices
    }

    /// All `LC_LOAD_DYLIB`-family entries across every slice, deduplicated
    /// by install name. Combines linked dylibs, weak-linked dylibs,
    /// re-exported dylibs, lazy-loaded dylibs, and upward-loaded dylibs.
    /// Convenient for callers that want the M1.3-deferred "what does this
    /// binary link against" answer in one call.
    public var linkedDylibs: [LoadCommand.Dylib] {
        var seen = Set<String>()
        var result: [LoadCommand.Dylib] = []
        for slice in slices {
            for command in slice.loadCommands {
                if let dylib = command.asLinkedDylib, !seen.contains(dylib.name) {
                    seen.insert(dylib.name)
                    result.append(dylib)
                }
            }
        }
        return result
    }
}

/// A single architecture's Mach-O image inside a `BinaryFile`.
///
/// `fileOffsetInBinary` is the byte offset where this slice's Mach-O image
/// begins within the overall file. `0` for a thin Mach-O; the value of the
/// corresponding `fat_arch.offset` for a slice inside a Universal binary.
/// Every offset on the slice's `Segment`s and `Section`s (`fileOffset`) is
/// relative to this base — add the two when reading from the underlying
/// file.
///
/// `symbols` is populated only when the caller passes `includeSymbols: true`
/// to `OWBinary.parse(at:)`. The three-state convention matches `OWProcess`:
/// `nil` when not captured, `[]` when capture was requested but the slice
/// has no `LC_SYMTAB` (stripped binary, or `LC_DYSYMTAB` only), populated
/// array otherwise.
public struct Slice: Sendable, Equatable, Hashable {
    public let architecture: Architecture
    public let fileType: FileType
    public let flags: UInt32
    public let fileOffsetInBinary: UInt64
    public let loadCommands: [LoadCommand]
    public let symbols: [Symbol]?

    public init(
        architecture: Architecture,
        fileType: FileType,
        flags: UInt32,
        fileOffsetInBinary: UInt64,
        loadCommands: [LoadCommand],
        symbols: [Symbol]? = nil
    ) {
        self.architecture = architecture
        self.fileType = fileType
        self.flags = flags
        self.fileOffsetInBinary = fileOffsetInBinary
        self.loadCommands = loadCommands
        self.symbols = symbols
    }
}

/// A single Mach-O symbol-table entry (`struct nlist` / `struct nlist_64`).
///
/// The Mach-O symbol table is a unified table containing every symbol the
/// binary defines, imports, exports, or carries as debug information. Each
/// entry's classification lives in the `n_type` byte; this type unpacks that
/// byte into Swift-friendly fields.
///
/// For external symbols (`isExternal == true`):
/// - `.undefined` entries are **imports** — names this binary uses but
///   relies on the linker / dyld to resolve from another image.
/// - `.defined` entries are **exports** — names this binary makes
///   available to other images linking against it.
///
/// `.stab` entries are STABS-format debugging information (file paths,
/// line numbers, etc.); they're not "real" symbols in the link-time sense.
public struct Symbol: Sendable, Equatable, Hashable {
    public let name: String
    public let kind: Kind
    /// For defined symbols: the address (image-relative virtual address)
    /// of the symbol in the loaded binary. For undefined / absolute / stab
    /// entries: the raw `n_value` field (often 0).
    public let value: UInt64
    /// `n_type & N_EXT != 0` — visible across translation units / dylibs.
    public let isExternal: Bool
    /// `n_type & N_PEXT != 0` — "private external"; the symbol was
    /// originally external but linker scoping has hidden it.
    public let isPrivateExternal: Bool
    /// 1-based section index for `.defined` symbols, 0 for everything else.
    public let sectionIndex: UInt8
    /// Raw `n_desc` field — version info, library ordinal for imports,
    /// reference flags, etc. Preserved for callers that need to decode it.
    public let descriptionBits: UInt16

    public enum Kind: Sendable, Equatable, Hashable {
        /// `N_UNDF` — name used but defined elsewhere (an import).
        case undefined
        /// `N_ABS` — symbol with a fixed value, not bound to any section.
        case absolute
        /// `N_SECT` — defined in section `sectionIndex`.
        case defined
        /// `N_PBUD` — prebound undefined (legacy prebinding optimization).
        case prebound
        /// `N_INDR` — alias for another symbol; `value` is a string-table
        /// offset to the target name.
        case indirect
        /// `N_STAB` — STABS-format debug entry. `rawType` is the full
        /// 8-bit `n_type` so callers that need to decode the specific
        /// stab type (N_SO, N_FUN, ...) can switch on it.
        case stab(rawType: UInt8)
    }

    public init(
        name: String,
        kind: Kind,
        value: UInt64,
        isExternal: Bool,
        isPrivateExternal: Bool,
        sectionIndex: UInt8,
        descriptionBits: UInt16
    ) {
        self.name = name
        self.kind = kind
        self.value = value
        self.isExternal = isExternal
        self.isPrivateExternal = isPrivateExternal
        self.sectionIndex = sectionIndex
        self.descriptionBits = descriptionBits
    }

    /// `nm(1)`-style single-character type code. Uppercase for external,
    /// lowercase for local. Lossy compared to the structured `kind` /
    /// `isExternal` / `sectionIndex` fields but useful for compact display.
    public var nmCode: Character {
        let code: Character
        switch kind {
        case .undefined: code = "u"
        case .absolute: code = "a"
        case .defined: code = "s"  // we don't yet distinguish text/data sections
        case .prebound: code = "p"
        case .indirect: code = "i"
        case .stab: code = "-"  // stab entries have no nm code; '-' is a placeholder
        }
        return isExternal ? Character(code.uppercased()) : code
    }
}

/// The architecture of a Mach-O slice.
///
/// Values derived from `cpu_type_t` in `<mach/machine.h>`. The unrecognized
/// case preserves the raw `cpuType` so callers that care can switch on it.
public enum Architecture: Sendable, Equatable, Hashable {
    case i386
    case x86_64
    case arm
    case arm64
    case arm64_32
    case unknown(cpuType: Int32)

    init(rawCPUType: Int32) {
        switch rawCPUType {
        case 7: self = .i386
        case 0x01000007: self = .x86_64
        case 12: self = .arm
        case 0x0100000C: self = .arm64
        case 0x0200000C: self = .arm64_32
        default: self = .unknown(cpuType: rawCPUType)
        }
    }

    /// Short human-readable form (matches the conventional Apple names
    /// printed by `file(1)` and `lipo -info`).
    public var name: String {
        switch self {
        case .i386: return "i386"
        case .x86_64: return "x86_64"
        case .arm: return "arm"
        case .arm64: return "arm64"
        case .arm64_32: return "arm64_32"
        case .unknown(let cpuType): return "unknown(\(cpuType))"
        }
    }
}

/// Mach-O file type from `mach_header.filetype` (`MH_*` constants).
public enum FileType: Sendable, Equatable, Hashable {
    case object
    case executable
    case fixedVMLibrary
    case core
    case preload
    case dylib
    case dynamicLinker
    case bundle
    case dylibStub
    case dSYM
    case kextBundle
    case fileset
    case other(rawType: UInt32)

    init(rawType: UInt32) {
        switch rawType {
        case 0x1: self = .object
        case 0x2: self = .executable
        case 0x3: self = .fixedVMLibrary
        case 0x4: self = .core
        case 0x5: self = .preload
        case 0x6: self = .dylib
        case 0x7: self = .dynamicLinker
        case 0x8: self = .bundle
        case 0x9: self = .dylibStub
        case 0xA: self = .dSYM
        case 0xB: self = .kextBundle
        case 0xC: self = .fileset
        default: self = .other(rawType: rawType)
        }
    }

    public var name: String {
        switch self {
        case .object: return "object"
        case .executable: return "executable"
        case .fixedVMLibrary: return "fixed-vm-library"
        case .core: return "core"
        case .preload: return "preload"
        case .dylib: return "dylib"
        case .dynamicLinker: return "dyld"
        case .bundle: return "bundle"
        case .dylibStub: return "dylib-stub"
        case .dSYM: return "dSYM"
        case .kextBundle: return "kext-bundle"
        case .fileset: return "fileset"
        case .other(let raw): return "other(\(String(raw, radix: 16)))"
        }
    }
}

/// A parsed Mach-O load command.
///
/// The variants cover the surface that matters for an EDR's binary
/// inspection: dynamic-library linkage (`Dylib`), runtime search paths
/// (`Rpath`), identity (`UUID`), entry point (`Main`), and memory layout
/// (`Segment`). Everything else is `.other(rawType:)` with the raw `cmd`
/// value preserved.
public enum LoadCommand: Sendable, Equatable, Hashable {
    /// LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB,
    /// LC_LAZY_LOAD_DYLIB, LC_LOAD_UPWARD_DYLIB, LC_ID_DYLIB.
    case dylib(Dylib)

    /// LC_RPATH — a runtime search path entry.
    case rpath(path: String)

    /// LC_UUID — the build's content-derived UUID.
    case uuid(UUID)

    /// LC_MAIN — entry point offset and initial stack size.
    case main(entryOffset: UInt64, stackSize: UInt64)

    /// LC_SEGMENT (32-bit) or LC_SEGMENT_64. Defines a region of the binary
    /// that maps into memory, including the sections within it.
    case segment(Segment)

    /// Any other load command. The raw 32-bit `cmd` value is preserved so
    /// callers can match against constants from `<mach-o/loader.h>`.
    case other(rawType: UInt32)

    public struct Dylib: Sendable, Equatable, Hashable {
        /// The load command's raw `cmd` value (e.g., `LC_LOAD_DYLIB = 0x0C`
        /// or `LC_LOAD_WEAK_DYLIB = 0x80000018`). Lets callers distinguish
        /// "required" vs. "weak" vs. "re-exported" linkage.
        public let rawCommand: UInt32
        /// The dylib's install name, e.g. `/usr/lib/libSystem.B.dylib`.
        public let name: String
        public let timestamp: UInt32
        public let currentVersion: UInt32
        public let compatibilityVersion: UInt32

        public init(
            rawCommand: UInt32,
            name: String,
            timestamp: UInt32,
            currentVersion: UInt32,
            compatibilityVersion: UInt32
        ) {
            self.rawCommand = rawCommand
            self.name = name
            self.timestamp = timestamp
            self.currentVersion = currentVersion
            self.compatibilityVersion = compatibilityVersion
        }

        /// True for `LC_LOAD_WEAK_DYLIB` and `LC_LAZY_LOAD_DYLIB`.
        public var isWeak: Bool {
            return rawCommand == 0x80000018 || rawCommand == 0x20
        }

        /// True for `LC_ID_DYLIB` (this binary IS the named dylib).
        public var isSelfIdentity: Bool {
            return rawCommand == 0x0D
        }
    }

    /// If this is a dylib-linkage command (not the self-identity
    /// `LC_ID_DYLIB`), returns the `Dylib` payload. Convenience for
    /// `BinaryFile.linkedDylibs`.
    public var asLinkedDylib: Dylib? {
        guard case let .dylib(payload) = self, !payload.isSelfIdentity else { return nil }
        return payload
    }
}

// MARK: - Segments + sections (M2.3)

/// A single Mach-O segment (`LC_SEGMENT` / `LC_SEGMENT_64`).
///
/// A segment is a contiguous region of the binary that the dynamic linker
/// maps into the process's address space. Each segment carries virtual-
/// address layout, file-offset layout, VM protection bits, and zero or more
/// sections (sub-regions with their own names, like `__text` for code or
/// `__data` for initialized globals).
public struct Segment: Sendable, Equatable, Hashable {
    public let name: String              // e.g. "__TEXT", "__DATA", "__LINKEDIT"
    public let vmAddress: UInt64
    public let vmSize: UInt64
    public let fileOffset: UInt64        // offset within the slice (not the universal binary)
    public let fileSize: UInt64
    public let maxProtection: SegmentProtection
    public let initialProtection: SegmentProtection
    public let flags: UInt32
    public let sections: [Section]

    public init(
        name: String,
        vmAddress: UInt64,
        vmSize: UInt64,
        fileOffset: UInt64,
        fileSize: UInt64,
        maxProtection: SegmentProtection,
        initialProtection: SegmentProtection,
        flags: UInt32,
        sections: [Section]
    ) {
        self.name = name
        self.vmAddress = vmAddress
        self.vmSize = vmSize
        self.fileOffset = fileOffset
        self.fileSize = fileSize
        self.maxProtection = maxProtection
        self.initialProtection = initialProtection
        self.flags = flags
        self.sections = sections
    }
}

/// VM protection bitfield (`vm_prot_t` in `<mach/vm_prot.h>`).
///
/// Combinations to look for in EDR analysis:
/// - **`[.read, .execute]`** (`r-x`) — the conventional `__TEXT` permission,
///   safe and expected.
/// - **`[.read, .write]`** (`rw-`) — the conventional `__DATA` permission,
///   safe and expected.
/// - **`[.read, .write, .execute]`** (`rwx`) — *suspicious*. A segment that
///   is simultaneously writable and executable is a strong packing /
///   self-modifying-code signal and should never appear in a normal
///   release-built binary.
public struct SegmentProtection: OptionSet, Sendable, Equatable, Hashable {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }

    public static let read = SegmentProtection(rawValue: 0x01)     // VM_PROT_READ
    public static let write = SegmentProtection(rawValue: 0x02)    // VM_PROT_WRITE
    public static let execute = SegmentProtection(rawValue: 0x04)  // VM_PROT_EXECUTE

    /// Compact `chmod(1)`-style three-character form, e.g. `r-x`.
    public var symbolicForm: String {
        let r = contains(.read) ? "r" : "-"
        let w = contains(.write) ? "w" : "-"
        let x = contains(.execute) ? "x" : "-"
        return "\(r)\(w)\(x)"
    }
}

/// A single Mach-O section (`struct section` / `section_64`).
///
/// Sections are sub-regions within a segment. The `__TEXT` segment
/// typically contains `__text` (executable code), `__cstring` (read-only
/// string literals), `__const` (read-only initialized data), etc. The
/// `__DATA` segment typically contains `__data` (initialized data), `__bss`
/// (uninitialized data), `__la_symbol_ptr` (lazy-binding symbol pointers),
/// etc.
public struct Section: Sendable, Equatable, Hashable {
    public let name: String              // e.g. "__text", "__cstring", "__data"
    public let segmentName: String       // parent segment's name
    public let address: UInt64           // virtual address
    public let size: UInt64              // size in bytes
    public let fileOffset: UInt32        // offset within the slice
    public let flags: UInt32

    public init(
        name: String,
        segmentName: String,
        address: UInt64,
        size: UInt64,
        fileOffset: UInt32,
        flags: UInt32
    ) {
        self.name = name
        self.segmentName = segmentName
        self.address = address
        self.size = size
        self.fileOffset = fileOffset
        self.flags = flags
    }
}

/// Result of computing Shannon entropy over a section's file-backed bytes.
///
/// `entropy` is in bits per byte and ranges from 0.0 (every byte identical)
/// to 8.0 (perfectly uniform distribution). Compiled native code typically
/// scores 5.5–6.5; compressed or encrypted data scores above 7.5; pure
/// ASCII text scores around 4.0–4.5.
public struct SectionEntropy: Sendable, Equatable, Hashable {
    public let sliceIndex: Int
    public let segmentName: String
    public let sectionName: String
    public let entropy: Double
    public let size: UInt64

    public init(
        sliceIndex: Int,
        segmentName: String,
        sectionName: String,
        entropy: Double,
        size: UInt64
    ) {
        self.sliceIndex = sliceIndex
        self.segmentName = segmentName
        self.sectionName = sectionName
        self.entropy = entropy
        self.size = size
    }
}
