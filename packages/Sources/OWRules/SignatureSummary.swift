import Foundation
import OWCodeSigning

/// Compact, rule-queryable view of a code signature. Built once per
/// unique executable path during snapshot capture so rules iterating
/// the `signature` source pay one `SecStaticCode` inspection cost
/// for many rules.
///
/// Field naming converts the underlying `CodeSignature` Swift API
/// (camelCase) to snake_case to match the YAML rule format. The
/// `signature_type` field is mapped from `SignatureType.rawValue`
/// (camelCase) to snake_case explicitly so rule authors write
/// `signature_type: developer_id` instead of `developerID`.
public struct SignatureSummary: Sendable, Equatable, Hashable {
    public let path: String
    public let isSigned: Bool
    public let isValid: Bool
    public let signatureType: String  // snake_case form
    public let identifier: String?
    public let teamIdentifier: String?
    public let cdHashHex: String?
    public let authoritiesJoined: String
    public let flagsSymbolic: String
    public let hasHardenedRuntime: Bool
    public let hardenedRuntimeVersion: String?
    public let isStapledForNotarization: Bool
    public let entitlementsCount: Int

    public init(
        path: String,
        isSigned: Bool,
        isValid: Bool,
        signatureType: String,
        identifier: String?,
        teamIdentifier: String?,
        cdHashHex: String?,
        authoritiesJoined: String,
        flagsSymbolic: String,
        hasHardenedRuntime: Bool,
        hardenedRuntimeVersion: String?,
        isStapledForNotarization: Bool,
        entitlementsCount: Int
    ) {
        self.path = path
        self.isSigned = isSigned
        self.isValid = isValid
        self.signatureType = signatureType
        self.identifier = identifier
        self.teamIdentifier = teamIdentifier
        self.cdHashHex = cdHashHex
        self.authoritiesJoined = authoritiesJoined
        self.flagsSymbolic = flagsSymbolic
        self.hasHardenedRuntime = hasHardenedRuntime
        self.hardenedRuntimeVersion = hardenedRuntimeVersion
        self.isStapledForNotarization = isStapledForNotarization
        self.entitlementsCount = entitlementsCount
    }
}

extension SignatureSummary {
    /// Build a `SignatureSummary` from a parsed `CodeSignature`.
    /// `path` is the original file URL the signature was inspected
    /// from (the summary keeps it as the target ID for findings).
    static func make(from signature: CodeSignature) -> SignatureSummary {
        SignatureSummary(
            path: signature.url.path,
            isSigned: signature.isSigned,
            isValid: signature.isValid,
            signatureType: snakeCase(for: signature.signatureType),
            identifier: signature.identifier,
            teamIdentifier: signature.teamIdentifier,
            cdHashHex: signature.cdHashHex,
            authoritiesJoined: signature.authorities.joined(separator: " | "),
            flagsSymbolic: signature.flags.symbolicForm,
            hasHardenedRuntime: signature.hasHardenedRuntime,
            hardenedRuntimeVersion: signature.hardenedRuntimeVersion,
            isStapledForNotarization: signature.isStapledForNotarization,
            entitlementsCount: signature.entitlements?.count ?? 0
        )
    }

    /// Map `SignatureType` to the snake_case form rules use.
    /// `developerID` → `developer_id`, `appStore` → `app_store`, etc.
    /// Explicit table — auto-deriving from `rawValue` would surface
    /// the camelCase form, which clashes with the rule format's
    /// snake_case convention.
    private static func snakeCase(for type: SignatureType) -> String {
        switch type {
        case .unsigned: return "unsigned"
        case .adhoc: return "adhoc"
        case .developerID: return "developer_id"
        case .appleDeveloper: return "apple_developer"
        case .appStore: return "app_store"
        case .apple: return "apple"
        case .unknown: return "unknown"
        }
    }
}
