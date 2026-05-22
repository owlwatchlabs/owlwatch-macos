import Foundation

/// Parameters for a single `OWLog.query(_:)` invocation.
///
/// Translates to `log show` argv when the query runs. Every field is
/// optional / has a default; an empty query (`LogQuery()`) returns the
/// last ``defaultLimit`` records of `Default`-level entries across all
/// subsystems.
///
/// Filters compose with `AND`: a query with `subsystem ==
/// "com.apple.TCC"` *and* `process == "tccd"` returns only TCC-tagged
/// messages emitted by tccd. The free-form ``predicate`` is appended to
/// the same `AND` chain so callers can extend with whatever NSPredicate
/// expression they need.
public struct LogQuery: Sendable, Equatable {
    /// Default `--last` argument when no time range is specified.
    /// 200 keeps the snapshot small without missing the last few
    /// seconds of activity. Override via ``limit``.
    public static let defaultLimit: Int = 200

    /// `subsystem == ...` predicate shorthand. `nil` leaves the
    /// subsystem unconstrained.
    public var subsystem: String?

    /// `category == ...` predicate shorthand.
    public var category: String?

    /// `process == ...` predicate shorthand. Matches the basename
    /// `log show` reports (e.g. `tccd`, not the full path).
    public var process: String?

    /// `eventMessage CONTAINS ...` shorthand for full-text matching
    /// the rendered message.
    public var messageContains: String?

    /// Free-form NSPredicate expression appended to the AND chain.
    /// Use this when the shorthands above aren't enough — e.g.
    /// `processID == 1234 OR processID == 5678`.
    public var predicate: String?

    /// Earliest entry to return. Maps to `log show --start`.
    public var since: Date?

    /// Latest entry to return. Maps to `log show --end`.
    public var until: Date?

    /// Cap on the number of returned entries. Maps to `log show
    /// --last`. `nil` uses ``defaultLimit``.
    public var limit: Int?

    /// Include `Info`-level messages. Maps to `log show --info`.
    public var includeInfo: Bool

    /// Include `Debug`-level messages. Maps to `log show --debug`.
    /// `Error` and `Fault` are always included regardless.
    public var includeDebug: Bool

    public init(
        subsystem: String? = nil,
        category: String? = nil,
        process: String? = nil,
        messageContains: String? = nil,
        predicate: String? = nil,
        since: Date? = nil,
        until: Date? = nil,
        limit: Int? = nil,
        includeInfo: Bool = false,
        includeDebug: Bool = false
    ) {
        self.subsystem = subsystem
        self.category = category
        self.process = process
        self.messageContains = messageContains
        self.predicate = predicate
        self.since = since
        self.until = until
        self.limit = limit
        self.includeInfo = includeInfo
        self.includeDebug = includeDebug
    }
}

/// Errors thrown by ``OWLog/OWLog/query(_:)``.
public enum OWLogError: Error, Sendable, Equatable {
    /// `/usr/bin/log` exited with a non-zero status. The stderr
    /// excerpt is preserved for diagnostics.
    case logShowFailed(exitCode: Int32, stderr: String)
}
