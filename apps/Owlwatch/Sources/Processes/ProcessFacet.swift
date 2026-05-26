import Foundation

/// Stackable facets for the M18.4 Processes section. Each facet is
/// a boolean predicate over a `ProcessRowVM`; the list's filter
/// stacks them with AND (`Internet` ∧ `Unsigned` = unsigned binaries
/// that also talk to the public internet).
///
/// Spec: M18 brief §3 — facets are the user's primary triage axes.
/// Counts are computed live off the full row set so the chip labels
/// stay honest.
enum ProcessFacet: String, CaseIterable, Identifiable, Hashable {
    case flagged
    case unsigned
    case suspiciousPath
    case internetConn
    case listening
    case tcc
    case thirdParty
    case persistent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .flagged:        return "Flagged"
        case .unsigned:       return "Unsigned"
        case .suspiciousPath: return "Suspicious path"
        case .internetConn:   return "Internet"
        case .listening:      return "Listening"
        case .tcc:            return "TCC"
        case .thirdParty:     return "3rd-party"
        case .persistent:     return "Persistent"
        }
    }

    func matches(_ row: ProcessRowVM) -> Bool {
        switch self {
        case .flagged:        return row.ruleCount > 0
        case .unsigned:       return row.signer == .unsigned
        case .suspiciousPath: return row.isSuspiciousPath
        case .internetConn:   return row.scopes.contains(.internetPublic)
        case .listening:      return row.hasListener
        case .tcc:            return row.tccCount > 0
        case .thirdParty:     return row.signer == .developerID
        case .persistent:     return row.isPersistent
        }
    }
}
