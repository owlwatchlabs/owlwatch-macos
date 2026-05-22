import Foundation
import Security

/// Inspects the code signature of a Mach-O binary or signed bundle.
///
/// `OWCodeSigning` is the M3 companion to ``OWBinary``: where `OWBinary`
/// answers structural questions about the binary itself, `OWCodeSigning`
/// answers identity and integrity questions about *who* signed it and
/// *whether* the signature still seals what's on disk.
///
/// M3.1 covers the core surface — signature presence, structural validity,
/// classification of the signing identity (ad-hoc vs Developer ID vs
/// first-party Apple), Team ID, signing identifier, CDHash, certificate
/// chain, and the `SecCodeSignatureFlags` bits. Designated requirements,
/// notarization status, and entitlements land in M3.2 / M3.3.
///
/// Implementation: thin wrapper over `SecStaticCodeCreateWithPath` +
/// `SecCodeCopySigningInformation` + `SecStaticCodeCheckValidity`. We
/// deliberately do **not** parse the LC_CODE_SIGNATURE blob ourselves —
/// the Security framework already does that under the hood and we want to
/// inherit its CMS / CDHash handling rather than re-implement it.
public enum OWCodeSigning {
    /// Inspect the code signature at `url`.
    ///
    /// `url` may point at a Mach-O binary, an `.app` bundle, a framework,
    /// or any other code container the Security framework recognizes via
    /// `SecStaticCodeCreateWithPath`.
    ///
    /// Unsigned inputs are **not** an error: the returned ``CodeSignature``
    /// has ``CodeSignature/isSigned`` set to `false` and most fields
    /// blank. This matches `codesign -dvvv`'s behavior of treating unsigned
    /// as a normal result rather than a fault.
    ///
    /// - Throws: ``OWCodeSigningError/unreadable(url:status:message:)`` if
    ///   the file can't be opened as a static code object;
    ///   ``OWCodeSigningError/malformedSignature(url:status:message:)``
    ///   if a signature is present but the Security framework refuses to
    ///   surface it.
    public static func inspect(at url: URL) throws -> CodeSignature {
        let staticCode = try makeStaticCode(at: url)
        let info = try copySigningInformation(staticCode, url: url)

        let identifier = info[kSecCodeInfoIdentifier as String] as? String
        let teamIdentifier = info[kSecCodeInfoTeamIdentifier as String] as? String
        let cdHash = info[kSecCodeInfoUnique as String] as? Data
        let format = info[kSecCodeInfoFormat as String] as? String
        let flags = SignatureFlags(rawValue: info[kSecCodeInfoFlags as String] as? UInt32 ?? 0)
        let authorities = extractAuthorities(from: info)
        let isSigned = !authorities.isEmpty || cdHash != nil || identifier != nil
        let isValid = isSigned && checkValidity(staticCode)
        let signatureType = classify(isSigned: isSigned, flags: flags, authorities: authorities)
        let designatedRequirement = isSigned ? designatedRequirementText(staticCode) : nil
        let stapledTicket = info["stapled-ticket"] as? Data
        let runtimeVersion = decodeRuntimeVersion(info["runtime-version"] as? Int)

        return CodeSignature(
            url: url,
            isSigned: isSigned,
            isValid: isValid,
            signatureType: signatureType,
            identifier: identifier,
            teamIdentifier: teamIdentifier,
            cdHash: cdHash,
            authorities: authorities,
            flags: flags,
            format: format,
            designatedRequirement: designatedRequirement,
            stapledNotarizationTicket: stapledTicket,
            hardenedRuntimeVersion: runtimeVersion
        )
    }
}

private func makeStaticCode(at url: URL) throws -> SecStaticCode {
    var staticCodeOpt: SecStaticCode?
    let status = SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(rawValue: 0), &staticCodeOpt)
    guard status == errSecSuccess, let staticCode = staticCodeOpt else {
        throw OWCodeSigningError.unreadable(url: url, status: status, message: secErrorMessage(status))
    }
    return staticCode
}

private func copySigningInformation(_ code: SecStaticCode, url: URL) throws -> [String: Any] {
    var infoOpt: CFDictionary?
    let infoFlags = UInt32(kSecCSSigningInformation | kSecCSContentInformation)
    let status = SecCodeCopySigningInformation(
        code,
        SecCSFlags(rawValue: infoFlags),
        &infoOpt
    )
    switch status {
    case errSecSuccess:
        return (infoOpt as? [String: Any]) ?? [:]
    case errSecCSUnsigned:
        return [:]
    default:
        throw OWCodeSigningError.malformedSignature(
            url: url,
            status: status,
            message: secErrorMessage(status)
        )
    }
}

private func checkValidity(_ code: SecStaticCode) -> Bool {
    SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: 0), nil) == errSecSuccess
}

private func designatedRequirementText(_ code: SecStaticCode) -> String? {
    var requirement: SecRequirement?
    guard SecCodeCopyDesignatedRequirement(code, SecCSFlags(rawValue: 0), &requirement) == errSecSuccess,
          let req = requirement else {
        return nil
    }
    var text: CFString?
    guard SecRequirementCopyString(req, SecCSFlags(rawValue: 0), &text) == errSecSuccess,
          let str = text as String? else {
        return nil
    }
    return str
}

private func decodeRuntimeVersion(_ raw: Int?) -> String? {
    guard let raw, raw > 0 else { return nil }
    let major = (raw >> 16) & 0xff
    let minor = (raw >> 8) & 0xff
    let patch = raw & 0xff
    return "\(major).\(minor).\(patch)"
}

private func extractAuthorities(from info: [String: Any]) -> [String] {
    guard let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate] else {
        return []
    }
    var names: [String] = []
    for cert in certs {
        var cn: CFString?
        let status = SecCertificateCopyCommonName(cert, &cn)
        if status == errSecSuccess, let name = cn as String? {
            names.append(name)
        }
    }
    return names
}

private func classify(
    isSigned: Bool,
    flags: SignatureFlags,
    authorities: [String]
) -> SignatureType {
    guard isSigned else { return .unsigned }
    if flags.contains(.adhoc) { return .adhoc }
    guard let leaf = authorities.first else { return .unknown }

    if leaf.hasPrefix("Developer ID Application") || leaf.hasPrefix("Developer ID Installer") {
        return .developerID
    }
    if leaf.hasPrefix("Apple Development") || leaf.hasPrefix("Mac Developer") {
        return .appleDeveloper
    }
    if leaf.hasPrefix("Apple Distribution") || leaf.hasPrefix("3rd Party Mac Developer") {
        return .appStore
    }
    let firstPartyLeaves: Set<String> = [
        "Software Signing",
        "Apple iPhone OS Application Signing",
        "Apple Mac OS Application Signing"
    ]
    if firstPartyLeaves.contains(leaf) {
        return .apple
    }
    if authorities.contains("Apple Root CA")
        && authorities.contains(where: { $0.contains("Apple") && $0.contains("Signing") }) {
        return .apple
    }
    return .unknown
}

private func secErrorMessage(_ status: OSStatus) -> String {
    if let cfMsg = SecCopyErrorMessageString(status, nil) {
        return cfMsg as String
    }
    return "OSStatus \(status)"
}
