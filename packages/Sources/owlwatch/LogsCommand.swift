import ArgumentParser
import Foundation
import OWLog

struct LogsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "logs",
        abstract: "Query macOS unified-log entries (os_log) with subsystem / process / message filters.",
        discussion: """
            Wraps /usr/bin/log show --style ndjson and renders the result \
            as a compact one-row-per-entry table. Default behavior matches \
            `log show`: only Default-level messages are returned (plus \
            Error and Fault which are always included); pass --info or \
            --debug to widen the level set.

            Without --since / --until, the last N entries are returned \
            (--last <N>, default 200). With an explicit time range, every \
            entry in that range is returned.

            Filters compose with AND. Use --predicate to extend the \
            generated NSPredicate with arbitrary clauses.

            Examples:
              owlwatch logs --subsystem com.apple.TCC --last 50
              owlwatch logs --process tccd --info --message-contains denied
              owlwatch logs --lookback 60                    # last minute
              owlwatch logs --errors-only --lookback 3600    # last hour, errors only
              owlwatch logs --predicate 'processID == 1234'
            """
    )

    @Option(name: .long, help: "Filter by subsystem (e.g. com.apple.TCC).")
    var subsystem: String?

    @Option(name: .long, help: "Filter by category within the subsystem.")
    var category: String?

    @Option(name: .long, help: "Filter by process name (basename).")
    var process: String?

    @Option(name: .long, help: "Substring match against the rendered message.")
    var messageContains: String?

    @Option(name: .long, help: "Raw NSPredicate expression appended to the AND chain.")
    var predicate: String?

    @Option(name: .long, help: "Seconds to look back from now (shortcut for --since).")
    var lookback: TimeInterval?

    @Option(
        name: .long,
        help: "Earliest entry to return as ISO-8601 (`2026-05-22T15:00:00`)."
    )
    var since: String?

    @Option(
        name: .long,
        help: "Latest entry to return as ISO-8601."
    )
    var until: String?

    @Option(name: .long, help: "Cap on rows returned when no time range is set.")
    var last: Int?

    @Flag(name: .long, help: "Include Info-level messages.")
    var info: Bool = false

    @Flag(name: .long, help: "Include Debug-level messages.")
    var debug: Bool = false

    @Flag(name: .long, help: "Only show Error and Fault entries.")
    var errorsOnly: Bool = false

    func run() throws {
        var query = LogQuery(
            subsystem: subsystem,
            category: category,
            process: process,
            messageContains: messageContains,
            predicate: predicate,
            includeInfo: info,
            includeDebug: debug
        )
        if let lookback {
            query.since = Date().addingTimeInterval(-lookback)
        } else if let since {
            query.since = parseISODate(since)
        }
        if let until {
            query.until = parseISODate(until)
        }
        query.limit = last

        var entries = try OWLog.query(query)
        if errorsOnly {
            entries = entries.filter { $0.level == .error || $0.level == .fault }
        }
        printTable(entries: entries)
    }

    private func parseISODate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) { return date }
        // Accept the simpler form "yyyy-MM-dd HH:mm:ss".
        let fallback = DateFormatter()
        fallback.dateFormat = "yyyy-MM-dd HH:mm:ss"
        fallback.locale = Locale(identifier: "en_US_POSIX")
        return fallback.date(from: string)
    }

    private func printTable(entries: [LogEntry]) {
        if entries.isEmpty {
            print("(no log entries matched the query)")
            return
        }
        let header = ["TIMESTAMP", "LEVEL", "PROCESS", "SUBSYSTEM", "CATEGORY", "MESSAGE"]
        let rows = entries.map(renderRow)
        let widths = columnWidths(header: header, rows: rows)
        print(formatRow(header, widths: widths))
        for row in rows {
            print(formatRow(row, widths: widths))
        }
    }

    private func renderRow(_ entry: LogEntry) -> [String] {
        let timestamp = renderTimestamp(entry.timestamp)
        let level = renderLevel(entry.level)
        let process = entry.processName ?? "-"
        let subsystem = entry.subsystem ?? "-"
        let category = entry.category ?? "-"
        let message = entry.message.replacingOccurrences(of: "\n", with: " ")
        return [timestamp, level, process, subsystem, category, message]
    }

    private func renderTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private func renderLevel(_ level: LogLevel) -> String {
        switch level {
        case .default: return "default"
        case .info: return "info"
        case .debug: return "debug"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        }
    }

    private func columnWidths(header: [String], rows: [[String]]) -> [Int] {
        var widths = header.map { $0.count }
        for row in rows {
            for (index, cell) in row.enumerated() where index < widths.count {
                // Cap message column at 100 chars; let it overflow visually rather
                // than blowing up the table width.
                let cap = index == widths.count - 1 ? 100 : 80
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
