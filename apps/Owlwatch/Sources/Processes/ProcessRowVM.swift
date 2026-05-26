import Foundation
import OWProcess
import OWRules
import OWTriage
import SwiftUI

/// One row in the M18.4 faceted process list. Pure value type with
/// every field a join of M1's process snapshot + M4 connections +
/// M3 signature + M5 persistence + M13 rule findings.
///
/// Built by `ProcessListModel.refresh()`. Per the M18 brief §5,
/// heavy work (signature, rules) runs at refresh time and gets
/// cached; subsequent silent updates only mutate the lightweight
/// fields (M18.6's scope).
struct ProcessRowVM: Identifiable, Equatable, Hashable {
    // MARK: - Identity (lightweight)

    let pid: pid_t
    let parentPid: pid_t
    let name: String
    let path: String?
    let userId: uid_t

    // MARK: - Joined derivations

    /// Triage signer (M18.3 OWTriage). `.unsigned` when no path /
    /// signature inspect failed.
    let signer: Signer

    /// Unique network scopes seen across this process's connections.
    /// `internetPublic` membership is what the `Internet` facet
    /// keys off — explicitly distinct from any-socket.
    let scopes: Set<NetworkScope>

    /// Any socket in `LISTEN` state.
    let hasListener: Bool

    /// True when the process's executable path is referenced by a
    /// LaunchService / Login Item. M18.4 currently checks
    /// LaunchService.executablePath only (Login Items are gated
    /// behind sfltool — see M17.5 fix).
    let isPersistent: Bool

    /// TCC events attributed to this pid within the lookback
    /// window. Always 0 in M18.4 (TCC log query is too slow for
    /// the snapshot refresh path; sourced separately by the detail
    /// pane in M18.5+).
    let tccCount: Int

    /// `OWTriage.isSuspiciousPath(path)` evaluated at refresh time.
    let isSuspiciousPath: Bool

    /// Number of OWRules findings whose target is this pid.
    let ruleCount: Int

    /// Highest severity across the row's rule findings. `nil` when
    /// `ruleCount == 0`.
    let maxSeverity: Severity?

    var id: pid_t { pid }

    /// Free-text match used by the filter field. Matches against
    /// name, path, and the raw pid string.
    func matchesQuery(_ query: String) -> Bool {
        let needle = query.lowercased()
        if name.lowercased().contains(needle) { return true }
        if let path, path.lowercased().contains(needle) { return true }
        if String(pid).contains(needle) { return true }
        return false
    }

    /// Severity-dot color for the row (left of the name). Renders
    /// `.clear` when `maxSeverity == nil` so the layout stays
    /// stable but the dot is invisible.
    var severityColor: Color {
        guard let maxSeverity else { return .clear }
        switch maxSeverity {
        case .info:                 return .owlTextDim
        case .low:                  return .owlAmberDim
        case .medium:               return .owlAmber
        case .high, .critical:      return .owlRed
        }
    }
}
