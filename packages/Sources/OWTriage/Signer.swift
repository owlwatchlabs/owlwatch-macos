import OWCodeSigning

/// Triage-oriented signer classification.
///
/// Collapses `CodeSignature.signatureType`'s seven cases into four
/// buckets that map cleanly to the triage UX: Apple system code is
/// the expected baseline (de-emphasize), third-party Developer ID /
/// App Store is notable (stand out), unsigned/adhoc is alarming
/// (red), everything else is unknown.
///
/// Color rendering lives on the app side as a SwiftUI extension —
/// this enum is intentionally Foundation-free so it stays trivially
/// testable.
public enum Signer: Equatable, Hashable, Sendable {
    /// Apple first-party (`.apple`) or Apple Developer
    /// (`.appleDeveloper`). The expected case on a healthy macOS
    /// install — most processes you see are this.
    case apple

    /// Third-party Developer ID (`.developerID`) or App Store
    /// (`.appStore`). The trusted-but-not-Apple bucket.
    case developerID

    /// Unsigned, ad-hoc, or signed-but-structurally-invalid. The
    /// case that warrants attention.
    case unsigned

    /// Signed by something the M3 classifier didn't recognize
    /// (custom enterprise CA, re-signed binary).
    case unknown

    /// Build a `Signer` from a `CodeSignature`. `nil` (no signature
    /// inspected) collapses to `.unsigned` — the safest default for
    /// triage: a missing signature reads the same as an absent one.
    public init(_ signature: CodeSignature?) {
        guard let signature, signature.isSigned, signature.isValid else {
            self = .unsigned
            return
        }
        switch signature.signatureType {
        case .apple, .appleDeveloper:
            self = .apple
        case .developerID, .appStore:
            self = .developerID
        case .adhoc, .unsigned:
            self = .unsigned
        case .unknown:
            self = .unknown
        }
    }

    /// Short human-readable label for the row chip.
    public var label: String {
        switch self {
        case .apple:        return "Apple"
        case .developerID:  return "Developer ID"
        case .unsigned:     return "unsigned"
        case .unknown:      return "unknown"
        }
    }
}
