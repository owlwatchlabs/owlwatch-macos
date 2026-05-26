import OWTriage
import SwiftUI

/// SwiftUI color renderings for the M18.3 `OWTriage` derivations.
///
/// The triage emphasis from the M18 brief §1:
/// - **Apple** code is the expected noise on a healthy install → de-emphasize.
/// - **Developer ID** is the notable third-party signal → amber.
/// - **Unsigned** is alarming → red.
/// - **Unknown** signers fall in between → muted.
///
/// Network-scope colors are equivalent: only public-internet is
/// saturated; everything else (LAN, localhost, IPC, unknown)
/// recedes so the eye snaps to outbound traffic.

extension Signer {
    /// Triage color emphasis. Apple recedes, Developer ID stands
    /// out, unsigned alarms.
    var color: Color {
        switch self {
        case .apple:        return .owlTextDim
        case .developerID:  return .owlAmber
        case .unsigned:     return .owlRed
        case .unknown:      return .owlTextMuted
        }
    }
}

extension NetworkScope {
    /// Only the public-internet scope is saturated. Everything else
    /// (LAN / localhost / IPC / unknown) renders muted so a row
    /// reaching public addresses pops in the list.
    var color: Color {
        self == .internetPublic ? .owlBlue : .owlTextMuted
    }
}
