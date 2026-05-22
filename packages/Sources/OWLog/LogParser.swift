import Darwin
import Foundation

/// Parse `log show --style ndjson` output into ``LogEntry`` records.
///
/// One JSON object per line. Lines that fail to JSON-decode (header
/// messages, blank lines, status banners `log show` sometimes emits)
/// are skipped silently — the parser is tolerant and only drops
/// records that lack the minimum required fields (a parseable
/// timestamp and an `eventMessage`).
internal func parseLogShowNDJSON(_ output: String) -> [LogEntry] {
    var entries: [LogEntry] = []
    let decoder = JSONDecoder()
    let timestampFormatter = makeLogShowTimestampFormatter()

    output.enumerateLines { line, _ in
        guard let data = line.data(using: .utf8), !data.isEmpty else { return }
        guard let raw = try? decoder.decode(LogShowRecord.self, from: data) else { return }
        guard let entry = buildLogEntry(from: raw, formatter: timestampFormatter) else { return }
        entries.append(entry)
    }
    return entries
}

internal func buildLogEntry(
    from raw: LogShowRecord,
    formatter: DateFormatter
) -> LogEntry? {
    guard let timestamp = formatter.date(from: raw.timestamp) else { return nil }
    let message = raw.eventMessage ?? ""

    let processName: String? = raw.processImagePath.map {
        ($0 as NSString).lastPathComponent
    }
    // `truncatingIfNeeded` because the kernel sometimes reports
    // sentinel values like `-1` / `4294967294` (UID -2 / "nobody")
    // that overflow a plain `pid_t(value)` / `Int32(value)` cast.
    let pid: pid_t? = raw.processID.map { pid_t(truncatingIfNeeded: $0) }
    let uid: uid_t? = raw.userID.map { uid_t(truncatingIfNeeded: $0) }
    let activityID = raw.activityIdentifier ?? 0

    let level = raw.messageType.map(LogLevel.from(rawValue:)) ?? .default
    let eventType = raw.eventType.map(LogEventType.from(rawValue:)) ?? .log

    return LogEntry(
        timestamp: timestamp,
        processName: processName,
        processPath: raw.processImagePath,
        processID: pid,
        userID: uid,
        threadID: raw.threadID,
        subsystem: raw.subsystem?.isEmpty == false ? raw.subsystem : nil,
        category: raw.category?.isEmpty == false ? raw.category : nil,
        level: level,
        eventType: eventType,
        message: message,
        activityID: activityID
    )
}

/// The subset of fields we decode from each NDJSON line. Many fields
/// from `log show` output are intentionally absent here — backtrace
/// frames, image UUIDs, format strings, mach timestamps, trace IDs,
/// and so on. They're useful for crash diagnosis but bloat the
/// snapshot value type and add no detection value.
internal struct LogShowRecord: Decodable {
    let timestamp: String
    let messageType: String?
    let eventType: String?
    let subsystem: String?
    let category: String?
    let eventMessage: String?
    let processID: Int?
    let userID: Int?
    let threadID: UInt64?
    let processImagePath: String?
    let activityIdentifier: UInt64?
}

/// Construct a `DateFormatter` matching the `log show` timestamp
/// format, e.g. `"2026-05-22 17:19:23.220714-0300"`. The format pieces:
///
/// - `yyyy-MM-dd HH:mm:ss` — the obvious bits.
/// - `.SSSSSS` — six-digit microsecond fractional seconds.
/// - `xx` — ISO 8601 zone offset of the form `±HHMM` (no colon).
///
/// Locale-pinned to `en_US_POSIX` so the formatter is stable
/// regardless of the host locale.
internal func makeLogShowTimestampFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSxx"
    return formatter
}
