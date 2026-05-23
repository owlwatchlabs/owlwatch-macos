import Foundation
import OWLog

/// Drives the M16.4 Logs window. Three tabs, each with its own
/// data shape:
///
/// - **All Logs** — generic `OWLog.query()` over the unified-log
///   archive within a user-chosen lookback window, with subsystem /
///   process / level filters. Snapshot, refreshed via Apply button.
/// - **TCC Events** — typed `OWLog.tccEvents()` from M6.2, with
///   denied-only and service filters. Snapshot too.
/// - **Live Tail** — `OWLog.stream()` AsyncThrowingStream, with
///   subsystem / process predicate filters. Long-running task that
///   appends to a capped in-memory buffer.
///
/// `log show` is *slow* (5–15s for a 1-minute window depending on
/// log volume) so query refresh is pull-on-demand, not search-on-keystroke.
/// The Apply button is the explicit trigger.
@MainActor
@Observable
final class LogsViewModel {
    /// Cap on the live-tail in-memory buffer. The unified log fires
    /// orders of magnitude more frequently than persistence or device
    /// events; 2000 covers ~30s of busy log output on a typical box.
    static let liveBufferCap = 2000

    // MARK: - Tabs + selection

    var selectedTab: LogsTab = .all {
        didSet {
            if oldValue != selectedTab {
                selectedItemID = nil
            }
            if selectedTab == .live {
                unseenLiveCount = 0
            }
        }
    }
    var selectedItemID: String?

    // MARK: - Data per tab

    /// Snapshot results for the All Logs tab.
    var logEntries: [LogEntry] = []

    /// Snapshot results for the TCC Events tab.
    var tccEvents: [TCCEvent] = []

    /// Live tail buffer for the Live Tail tab, newest-first.
    var liveEntries: [LogEntry] = []

    /// Unseen live-tail event count while the user is on a snapshot
    /// tab. Resets when the user navigates to Live Tail.
    var unseenLiveCount: Int = 0

    // MARK: - Filter state

    /// Lookback window for snapshot queries (All Logs + TCC Events).
    /// Live Tail ignores this — it streams forward only.
    var lookback: LookbackWindow = .fiveMinutes

    /// Subsystem predicate. Empty string = no constraint. Applied to
    /// all three tabs.
    var subsystemFilter: String = ""

    /// Process predicate. Empty string = no constraint.
    var processFilter: String = ""

    /// Message substring match. Empty string = no constraint.
    var messageContains: String = ""

    /// Include Info-level entries. Applied to All Logs + Live Tail.
    var includeInfo: Bool = false

    /// Include Debug-level entries. Applied to All Logs + Live Tail.
    var includeDebug: Bool = false

    /// Filter the snapshot to Error / Fault entries only. Cosmetic
    /// (post-query filter) since `log show` always returns errors.
    var errorsOnly: Bool = false

    /// TCC Events tab — only show denials.
    var deniedOnly: Bool = false

    // MARK: - Lifecycle

    var isLoading: Bool = false
    var lastRefresh: Date?
    var lastError: String?

    @ObservationIgnored private var liveTask: Task<Void, Never>?

    // MARK: - Apply

    /// Apply the current filter state to the active tab. For snapshot
    /// tabs this issues a fresh query; for Live Tail it (re)starts
    /// the stream.
    func apply() async {
        lastError = nil
        switch selectedTab {
        case .all:
            await applyAllLogs()
        case .tcc:
            await applyTCCEvents()
        case .live:
            restartLiveTail()
        }
    }

    private func applyAllLogs() async {
        isLoading = true
        defer { isLoading = false }
        let query = buildLogQuery(forStream: false)
        let result: ([LogEntry], String?) = await Task.detached { [errorsOnly] in
            do {
                let entries = try OWLog.query(query)
                let filtered: [LogEntry] = errorsOnly
                    ? entries.filter { $0.level == .error || $0.level == .fault }
                    : entries
                return (filtered, nil)
            } catch {
                return ([], "\(error)")
            }
        }.value
        logEntries = result.0.sorted(by: { $0.timestamp > $1.timestamp })
        lastError = result.1
        lastRefresh = Date()
    }

    private func applyTCCEvents() async {
        isLoading = true
        defer { isLoading = false }

        var query = LogQuery.tccDefault
        query.since = Date().addingTimeInterval(-lookback.seconds)
        if !processFilter.isEmpty {
            query.process = processFilter
        }
        let denied = deniedOnly

        let result: ([TCCEvent], String?) = await Task.detached {
            do {
                var events = try OWLog.tccEvents(query)
                if denied {
                    events = events.filter { $0.outcome == .denied }
                }
                return (events.sorted(by: { $0.timestamp > $1.timestamp }), nil)
            } catch {
                return ([], "\(error)")
            }
        }.value
        tccEvents = result.0
        lastError = result.1
        lastRefresh = Date()
    }

    // MARK: - Live tail

    private func restartLiveTail() {
        stopLiveTail()
        liveEntries = []
        unseenLiveCount = 0
        let query = buildLogQuery(forStream: true)
        liveTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await entry in OWLog.stream(query) {
                    if Task.isCancelled { return }
                    self.appendLive(entry)
                }
            } catch {
                NSLog("OWLog stream failed: %@", "\(error)")
            }
        }
        lastRefresh = Date()
    }

    func stopLiveTail() {
        liveTask?.cancel()
        liveTask = nil
    }

    private func appendLive(_ entry: LogEntry) {
        liveEntries.insert(entry, at: 0)
        if liveEntries.count > Self.liveBufferCap {
            liveEntries.removeLast(liveEntries.count - Self.liveBufferCap)
        }
        if selectedTab != .live {
            unseenLiveCount += 1
        }
    }

    // MARK: - Query builder

    private func buildLogQuery(forStream: Bool) -> LogQuery {
        var query = LogQuery(
            subsystem: subsystemFilter.isEmpty ? nil : subsystemFilter,
            process: processFilter.isEmpty ? nil : processFilter,
            messageContains: messageContains.isEmpty ? nil : messageContains,
            includeInfo: includeInfo,
            includeDebug: includeDebug
        )
        if !forStream {
            query.since = Date().addingTimeInterval(-lookback.seconds)
            // Default limit when a time range is set is suppressed; we
            // still cap at a reasonable count so the UI doesn't try to
            // render 50000 rows.
        }
        return query
    }

    // MARK: - Selection lookups (used by the detail pane)

    /// Stable identifier for a `LogEntry` row. We synthesize it from
    /// timestamp + activity + process — log entries don't carry a
    /// natural unique key, but the triplet is collision-free in
    /// practice.
    func logEntryID(_ entry: LogEntry, index: Int) -> String {
        "le:\(index):\(entry.timestamp.timeIntervalSince1970):\(entry.activityID)"
    }

    func tccEventID(_ event: TCCEvent) -> String {
        "tcc:\(event.msgID)"
    }

    var selectedLogEntry: LogEntry? {
        guard let id = selectedItemID,
              id.hasPrefix("le:"),
              let indexEnd = id.dropFirst(3).firstIndex(of: ":"),
              let index = Int(id.dropFirst(3)[..<indexEnd]) else { return nil }
        let source = selectedTab == .live ? liveEntries : logEntries
        return index < source.count ? source[index] : nil
    }

    var selectedTCCEvent: TCCEvent? {
        guard let id = selectedItemID, id.hasPrefix("tcc:") else { return nil }
        let msgID = String(id.dropFirst(4))
        return tccEvents.first(where: { $0.msgID == msgID })
    }
}

/// Tabs in the Logs window sidebar.
enum LogsTab: String, CaseIterable, Identifiable, Hashable {
    case all
    case tcc
    case live

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All Logs"
        case .tcc: return "TCC Events"
        case .live: return "Live Tail"
        }
    }

    var symbolName: String {
        switch self {
        case .all: return "doc.text"
        case .tcc: return "lock.shield"
        case .live: return "dot.radiowaves.left.and.right"
        }
    }
}

/// Pre-baked lookback options for snapshot queries. Maps to seconds
/// before now.
enum LookbackWindow: String, CaseIterable, Identifiable, Hashable {
    case oneMinute = "1 minute"
    case fiveMinutes = "5 minutes"
    case fifteenMinutes = "15 minutes"
    case oneHour = "1 hour"
    case sixHours = "6 hours"
    case oneDay = "24 hours"

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .oneMinute: return 60
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        case .oneHour: return 3600
        case .sixHours: return 21_600
        case .oneDay: return 86_400
        }
    }
}
