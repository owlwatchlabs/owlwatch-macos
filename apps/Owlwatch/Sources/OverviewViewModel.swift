import Foundation
import OWDevices
import OWLog
import OWNetwork
import OWPersistence
import OWProcess

/// Drives the M18 Overview section (was the M16.1 Dashboard window).
/// Pulls a thin slice of every data source we ship and exposes it as
/// a few headline numbers + a recent-activity list. Heavy work (full
/// snapshots, log queries) runs off the main actor; results publish
/// back here on completion.
///
/// Refresh model: pull-on-demand. The Overview isn't trying to be a
/// live console — it's the at-a-glance "what does Owlwatch see?" view.
/// Live event streams (persistence mutations, device state changes,
/// log tail) live in the dedicated sections for those sources.
@MainActor
@Observable
final class OverviewViewModel {
    // MARK: - Headline counts

    var processCount: Int = 0
    var launchServiceCount: Int = 0
    var launchServiceUserCount: Int = 0
    /// `nil` = the Overview does not auto-fetch login items.
    /// `OWPersistence.loginItems()` shells out to `sfltool dumpbtm`,
    /// which prompts for the user password on Sonoma+. Surfacing
    /// the count on every Overview refresh would mean an auth
    /// prompt every time the user opens the app — unacceptable.
    /// The Persistence section fetches lazily when the user actually
    /// navigates to its Login Items sub-tab.
    var loginItemCount: Int?
    var loginItemEnabledCount: Int?
    var networkListenerCount: Int = 0
    var networkEstablishedCount: Int = 0
    var cameraCount: Int = 0
    var microphoneCount: Int = 0
    var deviceInUseCount: Int = 0

    // MARK: - Recent activity (last refresh's lookback window)

    /// TCC denials within ``recentLookbackSeconds``, newest-first.
    var recentTCCDenials: [TCCEvent] = []

    /// Error-level log entries within ``recentLookbackSeconds``.
    var recentErrorLogs: [LogEntry] = []

    var recentLookbackSeconds: TimeInterval = 300  // 5 minutes

    // MARK: - UI state

    var isLoading: Bool = false
    var lastRefresh: Date?
    var lastError: String?

    /// Pull every data source. Each one runs in its own detached task
    /// so a slow source (TCC log query) doesn't gate the others.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        lastError = nil

        async let processes = Task.detached {
            (try? OWProcess.all(includeArguments: false, includeOpenFiles: false)) ?? []
        }.value
        async let launchServices = Task.detached { OWPersistence.launchServices() }.value
        // Login items intentionally NOT fetched here — see the
        // loginItemCount declaration's docstring.
        async let connections = Task.detached { try? OWNetwork.snapshot() }.value
        async let cameras = Task.detached { OWDevices.cameras() }.value
        async let microphones = Task.detached { OWDevices.microphones() }.value
        async let tccDenials = Task.detached { [recentLookbackSeconds] in
            await fetchTCCDenials(lookback: recentLookbackSeconds)
        }.value
        async let errorLogs = Task.detached { [recentLookbackSeconds] in
            await fetchRecentErrorLogs(lookback: recentLookbackSeconds)
        }.value

        let services = await launchServices
        let conns = await connections ?? []
        let cams = await cameras
        let mics = await microphones

        processCount = await processes.count
        launchServiceCount = services.count
        launchServiceUserCount = services.filter { $0.scope == .userAgent }.count
        networkListenerCount = conns.filter(\.isListener).count
        networkEstablishedCount = conns.filter { $0.tcpState == .established }.count
        cameraCount = cams.count
        microphoneCount = mics.count
        deviceInUseCount = cams.filter(\.isInUse).count + mics.filter(\.isInUse).count
        recentTCCDenials = await tccDenials
        recentErrorLogs = await errorLogs
        lastRefresh = Date()
    }
}

// MARK: - Off-main fetch helpers

private func fetchTCCDenials(lookback: TimeInterval) async -> [TCCEvent] {
    var query = LogQuery.tccDefault
    query.since = Date().addingTimeInterval(-lookback)
    guard let events = try? OWLog.tccEvents(query) else { return [] }
    return events.filter { $0.outcome == .denied }
        .sorted(by: { $0.timestamp > $1.timestamp })
}

private func fetchRecentErrorLogs(lookback: TimeInterval) async -> [LogEntry] {
    var query = LogQuery()
    query.since = Date().addingTimeInterval(-lookback)
    query.limit = 500
    guard let entries = try? OWLog.query(query) else { return [] }
    return entries
        .filter { $0.level == .error || $0.level == .fault }
        .sorted(by: { $0.timestamp > $1.timestamp })
}
