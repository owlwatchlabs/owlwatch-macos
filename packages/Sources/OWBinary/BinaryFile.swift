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
public struct Slice: Sendable, Equatable, Hashable {
    public let architecture: Architecture
    public let fileType: FileType
    public let flags: UInt32
    public let loadCommands: [LoadCommand]

    public init(
        architecture: Architecture,
        fileType: FileType,
        flags: UInt32,
        loadCommands: [LoadCommand]
    ) {
        self.architecture = architecture
        self.fileType = fileType
        self.flags = flags
        self.loadCommands = loadCommands
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
/// (`Rpath`), identity (`UUID`), and entry point (`Main`). Everything else
/// is `.other(rawType:)` with the raw `cmd` value preserved.
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
