import Foundation

/// Severity of a rule's finding. Ordered low → high so callers can
/// compare with `<` and filter via `>= .high`.
public enum Severity: String, Sendable, Codable, CaseIterable, Comparable {
    case info
    case low
    case medium
    case high
    case critical

    private var rank: Int {
        switch self {
        case .info: return 0
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        case .critical: return 4
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }

    /// Compact uppercase form for terminal output (e.g. `HIGH`).
    public var displayName: String {
        rawValue.uppercased()
    }
}
