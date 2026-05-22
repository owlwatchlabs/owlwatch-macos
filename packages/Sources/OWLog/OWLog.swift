import Foundation

/// Query historical entries from macOS's unified logging archive
/// (`os_log`).
///
/// `OWLog` is the M6 companion to ``OWProcess`` / ``OWNetwork`` /
/// ``OWPersistence``: where those answer "what is on the box right
/// now?", `OWLog` answers "what just happened?". It's a snapshot
/// over historical logs — the live-stream equivalent is M6.3
/// (`--follow`) and the real-time security-decision stream is M8
/// (Endpoint Security).
///
/// Implementation: shells to `/usr/bin/log show --style ndjson` and
/// parses the NDJSON output. The `OSLogStore` Swift API would be
/// cleaner but it requires the private `com.apple.logging.local-store`
/// entitlement to read the system store; `log show` is what every
/// off-the-shelf macOS log-reading tool uses for the same reason.
///
/// For an EDR the high-value subsystems to query are
/// `com.apple.TCC` (privacy decisions), `com.apple.SecurityServer`
/// (signing / Keychain), `com.apple.LaunchServices` (app launches),
/// and `com.apple.spctl` (Gatekeeper). M6.2 adds typed event
/// extraction over those.
public enum OWLog {
    /// Query the unified log archive. Returns the matching entries in
    /// chronological order (oldest first), capped by
    /// `query.limit ?? LogQuery.defaultLimit`.
    ///
    /// - Throws: ``OWLogError/logShowFailed(exitCode:stderr:)`` when
    ///   `/usr/bin/log` returns non-zero. Empty result (no matches)
    ///   is not an error.
    public static func query(_ query: LogQuery = LogQuery()) throws -> [LogEntry] {
        let arguments = buildLogShowArguments(for: query)
        let result = try runLogShow(arguments: arguments)
        return parseLogShowNDJSON(result)
    }
}

// MARK: - Subprocess

private func runLogShow(arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
    process.arguments = arguments
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    do {
        try process.run()
    } catch {
        throw OWLogError.logShowFailed(
            exitCode: -1,
            stderr: "failed to spawn /usr/bin/log: \(error.localizedDescription)"
        )
    }
    let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
        throw OWLogError.logShowFailed(
            exitCode: process.terminationStatus,
            stderr: stderrText
        )
    }
    return String(data: stdoutData, encoding: .utf8) ?? ""
}

// MARK: - argv builder

internal func buildLogShowArguments(for query: LogQuery) -> [String] {
    var argv: [String] = ["show", "--style", "ndjson"]
    if query.includeInfo { argv.append("--info") }
    if query.includeDebug { argv.append("--debug") }

    if let since = query.since {
        argv.append("--start")
        argv.append(logShowDateString(since))
    }
    if let until = query.until {
        argv.append("--end")
        argv.append(logShowDateString(until))
    }

    if let predicate = buildPredicate(for: query) {
        argv.append("--predicate")
        argv.append(predicate)
    }

    // Only apply --last when no explicit time range was given.
    // `log show` rejects --last alongside --start/--end on some macOS
    // versions; when both are set, prefer the explicit time range.
    if query.since == nil && query.until == nil {
        argv.append("--last")
        argv.append(String(query.limit ?? LogQuery.defaultLimit))
    }
    return argv
}

internal func buildPredicate(for query: LogQuery) -> String? {
    var clauses: [String] = []
    if let subsystem = query.subsystem {
        clauses.append("subsystem == \"\(escape(subsystem))\"")
    }
    if let category = query.category {
        clauses.append("category == \"\(escape(category))\"")
    }
    if let process = query.process {
        clauses.append("process == \"\(escape(process))\"")
    }
    if let messageContains = query.messageContains {
        clauses.append("eventMessage CONTAINS \"\(escape(messageContains))\"")
    }
    if let predicate = query.predicate, !predicate.isEmpty {
        clauses.append("(\(predicate))")
    }
    guard !clauses.isEmpty else { return nil }
    return clauses.joined(separator: " AND ")
}

/// Escape backslashes and double-quotes in a string we're about to
/// embed inside `log show --predicate '...'`. The predicate language
/// is NSPredicate-style; double-quotes delimit string literals and
/// backslashes escape themselves.
private func escape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

private func logShowDateString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.timeZone = TimeZone.current
    return formatter.string(from: date)
}
