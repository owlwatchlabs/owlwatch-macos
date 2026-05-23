import ArgumentParser
import Foundation
import OWLog

struct TccEventsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tcc-events",
        abstract: "Reconstruct typed TCC permission decisions from the unified log.",
        discussion: """
            Queries com.apple.TCC/access entries and correlates each \
            6-line transaction (REQUEST + AUTHREQ_CTX + AUTHREQ_ATTRIBUTION \
            + AUTHREQ_SUBJECT + AUTHREQ_RESULT + REPLY) into a single \
            TCCEvent showing which process asked for which permission and \
            whether tccd allowed it.

            The TCC events are tier-1 EDR signal: repeated denials suggest \
            probing, grants to unexpected binaries suggest social \
            engineering, and accessing/requesting divergence (e.g. \
            ContinuityCaptureAgent asking on behalf of WhatsApp) surfaces \
            delegation chains.

            Output columns: TIMESTAMP, OUTCOME, SERVICE, ACCESSING, REQUESTING.

            Examples:
              owlwatch tcc-events --lookback 600
              owlwatch tcc-events --denied-only
              owlwatch tcc-events --service kTCCServiceCamera
              owlwatch tcc-events --process WhatsApp
            """
    )

    @Option(name: .long, help: "Seconds to look back from now.")
    var lookback: TimeInterval?

    @Option(name: .long, help: "Earliest entry (ISO-8601 or 'YYYY-MM-DD HH:MM:SS').")
    var since: String?

    @Option(name: .long, help: "Latest entry (ISO-8601 or 'YYYY-MM-DD HH:MM:SS').")
    var until: String?

    @Option(name: .long, help: "Cap on log entries scanned (default 5000).")
    var last: Int?

    @Option(name: .long, help: "Filter to a single TCC service (e.g. kTCCServiceCamera).")
    var service: String?

    @Option(
        name: .long,
        help: "Filter to events where the accessing OR requesting process identifier contains this substring."
    )
    var process: String?

    @Flag(name: .long, help: "Only show denied requests.")
    var deniedOnly: Bool = false

    @Flag(name: .long, help: "Hide preflight requests (would-this-be-allowed checks).")
    var hidePreflight: Bool = false

    func run() throws {
        var query = LogQuery.tccDefault
        if let lookback {
            query.since = Date().addingTimeInterval(-lookback)
        } else if let since {
            query.since = parseISODate(since)
        }
        if let until {
            query.until = parseISODate(until)
        }
        // TCC transactions are 6 lines; scan a healthy multiple of the
        // desired event count by default so we don't truncate mid-group.
        query.limit = (last ?? 500) * 6

        var events = try OWLog.tccEvents(query)
        events = applyFilters(to: events)
        printTable(events: events)
    }

    private func applyFilters(to events: [TCCEvent]) -> [TCCEvent] {
        events.filter { event in
            if deniedOnly && event.outcome != .denied { return false }
            if hidePreflight && event.isPreflight { return false }
            if let service, event.service.rawValue != service { return false }
            if let process {
                let needle = process.lowercased()
                let accessingHit = event.accessingProcess?.identifier.lowercased().contains(needle) ?? false
                let requestingHit = event.requestingProcess?.identifier.lowercased().contains(needle) ?? false
                if !accessingHit && !requestingHit { return false }
            }
            return true
        }
    }

    private func parseISODate(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: string) { return date }
        let fallback = DateFormatter()
        fallback.dateFormat = "yyyy-MM-dd HH:mm:ss"
        fallback.locale = Locale(identifier: "en_US_POSIX")
        return fallback.date(from: string)
    }

    private func printTable(events: [TCCEvent]) {
        if events.isEmpty {
            print("(no TCC events matched the query)")
            return
        }
        let header = ["TIMESTAMP", "OUTCOME", "SERVICE", "ACCESSING", "REQUESTING"]
        let rows = events.map(renderRow)
        let widths = columnWidths(header: header, rows: rows)
        print(formatRow(header, widths: widths))
        for row in rows {
            print(formatRow(row, widths: widths))
        }
    }

    private func renderRow(_ event: TCCEvent) -> [String] {
        let ts = renderTimestamp(event.timestamp)
        let outcome = event.isPreflight
            ? "\(event.outcome.displayName) (preflight)"
            : event.outcome.displayName
        let service = event.service.rawValue
        let accessing = renderProcess(event.accessingProcess)
        let requesting = event.isDirectRequest ? "(same)" : renderProcess(event.requestingProcess)
        return [ts, outcome, service, accessing, requesting]
    }

    private func renderTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private func renderProcess(_ process: TCCProcessRef?) -> String {
        guard let process else { return "—" }
        return "\(process.identifier) (\(process.pid))"
    }

    private func columnWidths(header: [String], rows: [[String]]) -> [Int] {
        var widths = header.map { $0.count }
        for row in rows {
            for (index, cell) in row.enumerated() where index < widths.count {
                let cap = index == widths.count - 1 ? 80 : 60
                widths[index] = min(max(widths[index], cell.count), cap)
            }
        }
        return widths
    }

    private func formatRow(_ cells: [String], widths: [Int]) -> String {
        cells.enumerated()
            .map { index, cell in cell.padding(toLength: widths[index], withPad: " ", startingAt: 0) }
            .joined(separator: "  ")
            .trimmingCharacters(in: .whitespaces)
    }
}
