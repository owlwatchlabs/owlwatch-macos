import Foundation

/// Structural and identity information about a Mach-O / bundle code signature.
///
/// Populated by ``OWCodeSigning/OWCodeSigning/inspect(at:)`` from the
/// `SecStaticCode` API. Unsigned inputs are returned (not thrown): callers
/// inspect ``isSigned`` to distinguish "no signature" from "signature
/// present and well-formed."
///
/// Fields mirror what `codesign -dvvv` exposes for the M3.1 scope: signature
/// presence, structural validity, the signing-identity classification (ad-hoc
/// vs Developer ID vs first-party Apple), Team ID, signing identifier,
/// CDHash, certificate chain, and the `SecCodeSignatureFlags` bits.
///
/// Designated requirement, notarization status, and entitlements land in
/// M3.2 / M3.3.
public struct CodeSignature: Sendable, Equatable {
    /// The path that was inspected.
    public let url: URL

    /// `true` when a code signature is embedded in the binary or bundle.
    /// `false` for stripped or never-signed inputs.
    public let isSigned: Bool

    /// Structural validity — i.e. the signature is internally consistent and
    /// the sealed code matches the stored hashes. Does **not** imply
    /// Gatekeeper acceptance or that the certificate chain is currently
    /// trusted; that is M3.2's job.
    ///
    /// Always `false` when ``isSigned`` is `false`.
    public let isValid: Bool

    /// Classification of the signing identity, derived from
    /// `kSecCodeSignatureAdhoc` and the certificate chain. See
    /// ``SignatureType``.
    public let signatureType: SignatureType

    /// The signing identifier (`Identifier=` in `codesign -dvvv`). Typically
    /// looks like `com.apple.ls` or a bundle identifier; for binaries
    /// signed without an explicit `--identifier`, the linker derives it
    /// from the file name plus a random suffix.
    public let identifier: String?

    /// The Team Identifier. `nil` for ad-hoc, first-party Apple, and
    /// platform-binary signatures; populated for any signature using a
    /// developer-program-issued certificate.
    public let teamIdentifier: String?

    /// The CDHash — a hash of the CodeDirectory blob, used as the
    /// identity-of-record by AMFI and Gatekeeper. Hex-encoded form is
    /// available via ``cdHashHex``.
    public let cdHash: Data?

    /// Common Names from the signing certificate chain, leaf first
    /// (`leaf, intermediate, root`). Empty for ad-hoc and unsigned.
    public let authorities: [String]

    /// `SecCodeSignatureFlags` bits — hardened runtime, library-validation,
    /// linker-signed, etc. See ``SignatureFlags``.
    public let flags: SignatureFlags

    /// Human-readable format string from `kSecCodeInfoFormat`, e.g.
    /// `"Mach-O universal (x86_64 arm64e)"` or `"bundle with Mach-O thin
    /// (arm64)"`. `nil` if the Security framework didn't report one.
    public let format: String?

    /// Text form of the designated requirement — the predicate code-signing
    /// uses to identify "this" binary across versions and updates. Output
    /// of `SecRequirementCopyString` against the requirement returned by
    /// `SecCodeCopyDesignatedRequirement`. Example:
    /// `identifier "com.apple.ls" and anchor apple`. `nil` for unsigned
    /// inputs or when the binary has no embedded requirement.
    public let designatedRequirement: String?

    /// The embedded notarization ticket bytes (`stapled-ticket` from
    /// `SecCodeCopySigningInformation` with `kSecCSContentInformation`),
    /// `nil` when no ticket is stapled.
    ///
    /// **`nil` does NOT mean "not notarized."** A binary can be notarized
    /// online (verified against Apple's ticket service by Gatekeeper) but
    /// shipped without a stapled ticket — VS Code is the canonical
    /// example. To distinguish "notarized but unstapled" from "actually
    /// not notarized" requires an online check (e.g. `SecAssessment`,
    /// which lands in a later M3.x or M9). For the offline static
    /// inspection M3.2 ships, this field answers "does this bundle
    /// carry its own proof?" — which is what `stapler validate` checks.
    public let stapledNotarizationTicket: Data?

    /// Hardened-runtime version "X.Y.Z" the binary opts into, decoded from
    /// the `runtime-version` `SecCodeCopySigningInformation` key.
    /// Populated only when ``SignatureFlags/runtime`` is set. The version
    /// corresponds to the SDK the binary was built against — newer
    /// versions enable stricter library-load restrictions.
    public let hardenedRuntimeVersion: String?

    /// Entitlements granted by the signature, parsed from the
    /// `entitlements-dict` `SecCodeCopySigningInformation` key.
    ///
    /// Three states matter:
    /// - `nil` — no entitlements blob is embedded (most Apple system
    ///   binaries, locally-built ad-hoc).
    /// - `[:]` — blob is present but parses to an empty dictionary
    ///   (Rectangle.app does this — a structural placeholder).
    /// - populated — every entitlement the signature grants.
    ///
    /// Entitlement *names* are well-known strings like
    /// `com.apple.security.app-sandbox` or
    /// `com.apple.security.cs.allow-jit`. Values are typically `.bool`
    /// but can be any plist scalar or collection — see ``Entitlement``.
    public let entitlements: [String: Entitlement]?

    public init(
        url: URL,
        isSigned: Bool,
        isValid: Bool,
        signatureType: SignatureType,
        identifier: String?,
        teamIdentifier: String?,
        cdHash: Data?,
        authorities: [String],
        flags: SignatureFlags,
        format: String?,
        designatedRequirement: String? = nil,
        stapledNotarizationTicket: Data? = nil,
        hardenedRuntimeVersion: String? = nil,
        entitlements: [String: Entitlement]? = nil
    ) {
        self.url = url
        self.isSigned = isSigned
        self.isValid = isValid
        self.signatureType = signatureType
        self.identifier = identifier
        self.teamIdentifier = teamIdentifier
        self.cdHash = cdHash
        self.authorities = authorities
        self.flags = flags
        self.format = format
        self.designatedRequirement = designatedRequirement
        self.stapledNotarizationTicket = stapledNotarizationTicket
        self.hardenedRuntimeVersion = hardenedRuntimeVersion
        self.entitlements = entitlements
    }

    /// Lowercase hex form of ``cdHash`` (e.g. `"1205ca11b1c3..."`), or
    /// `nil` when no CDHash is available.
    public var cdHashHex: String? {
        guard let data = cdHash else { return nil }
        return data.map { String(format: "%02x", $0) }.joined()
    }

    /// `true` when the binary has a stapled notarization ticket. Convenience
    /// for `stapledNotarizationTicket != nil`. See
    /// ``stapledNotarizationTicket`` for the "online-notarized but not
    /// stapled" caveat.
    public var isStapledForNotarization: Bool {
        stapledNotarizationTicket != nil
    }

    /// `true` when the hardened-runtime flag is set. Convenience for
    /// `flags.contains(.runtime)`.
    public var hasHardenedRuntime: Bool {
        flags.contains(.runtime)
    }
}

/// Classification of the signing identity.
///
/// Derived by inspecting `kSecCodeSignatureAdhoc` and the certificate chain.
/// Owlwatch's higher-level layers — Gatekeeper-style decisions in M3.2,
/// detection rules in M13 — branch on this enum rather than re-parsing
/// authority strings.
public enum SignatureType: String, Sendable, Equatable, Hashable, CaseIterable {
    /// No signature is embedded.
    case unsigned

    /// Ad-hoc signed: a CodeDirectory is present but there is no signing
    /// certificate. The `kSecCodeSignatureAdhoc` flag is set. Default for
    /// locally-built unsigned binaries on Apple Silicon (the linker
    /// auto-applies ad-hoc); also used by ChromeBuild and some packagers.
    case adhoc

    /// Signed with a Developer ID certificate. Notarizable, distributable
    /// outside the App Store. Leaf CN starts with
    /// `"Developer ID Application"` or `"Developer ID Installer"`.
    case developerID

    /// Signed with a development certificate (`"Apple Development"` /
    /// `"Mac Developer"` leaf). Local debug builds with a real team
    /// identity attached.
    case appleDeveloper

    /// Signed for App Store distribution (`"Apple Distribution"` /
    /// `"3rd Party Mac Developer Application"` leaf).
    case appStore

    /// First-party Apple platform binary — system binaries, frameworks,
    /// the OS itself. Leaf CN like `"Software Signing"` or an
    /// `"Apple Mac OS Application Signing"` intermediate, chained to
    /// `"Apple Root CA"`.
    case apple

    /// Signed, certificate chain present, but the leaf doesn't match any
    /// of the known patterns. Custom enterprise CAs and re-signed binaries
    /// land here.
    case unknown
}

/// `SecCodeSignatureFlags` bits, mirrored from
/// `<Security/CSCommon.h>`. Owlwatch exposes them as an `OptionSet` so
/// detection rules can write `flags.contains(.runtime)` rather than masking
/// raw `UInt32`s.
///
/// The most operationally-relevant bits:
///
/// - ``runtime`` — the *hardened runtime*. Required for notarized
///   binaries on macOS 10.14+. Absent it on a Developer ID signature is a
///   signal that the binary was signed but not notarized.
/// - ``libraryValidation`` — the binary will only load libraries signed
///   by the same Team ID or by Apple. A common malware-evasion target
///   (clear this bit and a hijacked dylib loads).
/// - ``adhoc`` — see ``SignatureType/adhoc``.
/// - ``linkerSigned`` — ad-hoc applied by `ld` at link time, not by
///   `codesign(1)`. Indistinguishable from manual ad-hoc on inspection
///   but the linker bit is set.
public struct SignatureFlags: OptionSet, Sendable, Equatable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let host = SignatureFlags(rawValue: 0x0001)
    public static let adhoc = SignatureFlags(rawValue: 0x0002)
    public static let forceHard = SignatureFlags(rawValue: 0x0100)
    public static let forceKill = SignatureFlags(rawValue: 0x0200)
    public static let forceExpiration = SignatureFlags(rawValue: 0x0400)
    public static let restrict = SignatureFlags(rawValue: 0x0800)
    public static let enforcement = SignatureFlags(rawValue: 0x1000)
    public static let libraryValidation = SignatureFlags(rawValue: 0x2000)
    public static let runtime = SignatureFlags(rawValue: 0x10000)
    public static let linkerSigned = SignatureFlags(rawValue: 0x20000)

    /// Render set bits as a stable, space-separated string (e.g.
    /// `"runtime library-validation"`). Empty string when no bits are set.
    public var symbolicForm: String {
        var parts: [String] = []
        if contains(.host) { parts.append("host") }
        if contains(.adhoc) { parts.append("adhoc") }
        if contains(.forceHard) { parts.append("force-hard") }
        if contains(.forceKill) { parts.append("force-kill") }
        if contains(.forceExpiration) { parts.append("force-expiration") }
        if contains(.restrict) { parts.append("restrict") }
        if contains(.enforcement) { parts.append("enforcement") }
        if contains(.libraryValidation) { parts.append("library-validation") }
        if contains(.runtime) { parts.append("runtime") }
        if contains(.linkerSigned) { parts.append("linker-signed") }
        return parts.joined(separator: " ")
    }
}

/// Errors thrown by ``OWCodeSigning/OWCodeSigning``.
///
/// Unsigned inputs are **not** an error — they return a ``CodeSignature``
/// with ``CodeSignature/isSigned`` set to `false`. Errors are reserved for
/// the cases where we couldn't read the file or the Security framework
/// reported a hard failure.
public enum OWCodeSigningError: Error, Sendable, Equatable {
    /// The Security framework couldn't open the path — file missing,
    /// permission denied, or not a valid binary / bundle.
    case unreadable(url: URL, status: OSStatus, message: String)

    /// The signature is present but malformed in a way the Security
    /// framework refused to surface.
    case malformedSignature(url: URL, status: OSStatus, message: String)
}
