import Foundation

/// A kernel extension (kext) installed on disk.
///
/// Kexts are the legacy mechanism — Apple has been deprecating them in
/// favor of System Extensions since macOS 10.15. Some hardware vendors
/// (RAID controllers, audio interfaces, third-party file systems) still
/// ship kexts because they need privileged in-kernel APIs that
/// DriverKit / Endpoint Security don't yet cover.
///
/// `KernelExtension` is a *static* view: it inspects the on-disk
/// `.kext` bundle's `Info.plist`. It does **not** tell you whether the
/// kext is currently loaded into the running kernel; that requires
/// `kextstat` / `IOKit` queries and is deferred (M10's persistence
/// monitor will likely need it).
///
/// For an EDR, the detection-relevant facts are: *who installed it*
/// (``bundleIdentifier``, cross-reference with ``OWCodeSigning`` on
/// ``executablePath``) and *which scope* it lives in
/// (``KernelExtensionScope/system`` under `/Library/Extensions` is
/// third-party; ``KernelExtensionScope/platform`` under
/// `/System/Library/Extensions` is Apple). An unrecognized kext in
/// the system scope is high-priority signal.
public struct KernelExtension: Sendable, Equatable, Hashable {
    /// Absolute filesystem path to the `.kext` bundle.
    public let bundlePath: String

    /// Bundle identifier (`CFBundleIdentifier`) of the kext. `nil`
    /// for malformed bundles (the Info.plist exists but lacks the key
    /// — rare, but a tampered kext might).
    public let bundleIdentifier: String?

    /// `CFBundleShortVersionString` — the human-readable version.
    public let shortVersion: String?

    /// `CFBundleVersion` — build / revision.
    public let bundleVersion: String?

    /// `CFBundleExecutable` — the name of the binary inside the
    /// kext's `Contents/MacOS/` directory.
    public let executableName: String?

    /// Resolved full path to the kext's executable: `bundlePath` +
    /// `Contents/MacOS/<executableName>`. `nil` when
    /// ``executableName`` is `nil`. Hand this to `OWCodeSigning` to
    /// inspect the kext's signature.
    public let executablePath: String?

    /// Where the kext lives — first-party Apple under
    /// `/System/Library/Extensions` or third-party under
    /// `/Library/Extensions`. Detection rules typically scope to the
    /// third-party tree.
    public let scope: KernelExtensionScope

    public init(
        bundlePath: String,
        bundleIdentifier: String?,
        shortVersion: String?,
        bundleVersion: String?,
        executableName: String?,
        executablePath: String?,
        scope: KernelExtensionScope
    ) {
        self.bundlePath = bundlePath
        self.bundleIdentifier = bundleIdentifier
        self.shortVersion = shortVersion
        self.bundleVersion = bundleVersion
        self.executableName = executableName
        self.executablePath = executablePath
        self.scope = scope
    }
}

/// Where a kernel extension bundle lives.
public enum KernelExtensionScope: String, Sendable, Equatable, Hashable, CaseIterable {
    /// `/System/Library/Extensions` — Apple-shipped kexts (graphics
    /// drivers, audio drivers, the rest of the platform kernel
    /// surface). SIP-protected.
    case platform

    /// `/Library/Extensions` — third-party kexts installed by users or
    /// admin. Less common on modern macOS; the surface most likely
    /// to contain unauthorized or stale software.
    case system

    /// Filesystem path the scope corresponds to.
    public var directoryPath: String {
        switch self {
        case .platform: return "/System/Library/Extensions"
        case .system: return "/Library/Extensions"
        }
    }
}
