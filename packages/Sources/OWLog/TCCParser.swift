import Darwin
import Foundation

/// Internal builder for ``OWLog/OWLog/tccEvents(_:)``. Given a list
/// of ``LogEntry`` records — typically the result of a `subsystem ==
/// "com.apple.TCC"` query — groups them by `msgID` and extracts a
/// ``TCCEvent`` per transaction.
///
/// One TCC transaction is six lines: `REQUEST`, `AUTHREQ_CTX`,
/// `AUTHREQ_ATTRIBUTION`, `AUTHREQ_SUBJECT`, `AUTHREQ_RESULT`,
/// `REPLY` (and sometimes `requestor:` / `-[TCCDAccessIdentity
/// staticCode]` lines mixed in). Transactions missing the
/// `AUTHREQ_CTX` line (which carries `service=...`) are dropped —
/// without the service, the event has no detection value.
internal func buildTCCEvents(from entries: [LogEntry]) -> [TCCEvent] {
    var groups: [String: [LogEntry]] = [:]
    var msgIDOrder: [String] = []

    for entry in entries where entry.subsystem == "com.apple.TCC" {
        guard let msgID = extractMsgID(from: entry.message) else { continue }
        if groups[msgID] == nil {
            msgIDOrder.append(msgID)
        }
        groups[msgID, default: []].append(entry)
    }

    var events: [TCCEvent] = []
    events.reserveCapacity(msgIDOrder.count)
    for msgID in msgIDOrder {
        guard let group = groups[msgID], let event = buildTCCEvent(msgID: msgID, lines: group) else {
            continue
        }
        events.append(event)
    }
    return events
}

/// Build a single ``TCCEvent`` from the lines that share one `msgID`.
/// Returns `nil` when the group lacks an `AUTHREQ_CTX` line (no
/// service → no event).
internal func buildTCCEvent(msgID: String, lines: [LogEntry]) -> TCCEvent? {
    // Choose the earliest timestamp as the canonical event time.
    guard let earliest = lines.map(\.timestamp).min() else { return nil }

    var service: TCCService?
    var isPreflight = false
    var accessing: TCCProcessRef?
    var requesting: TCCProcessRef?
    var authValue: Int?
    var authReason: Int?

    for line in lines {
        let message = line.message
        if message.hasPrefix("AUTHREQ_CTX") {
            if let (svc, preflight) = parseAuthreqCTX(message) {
                service = svc
                isPreflight = preflight
            }
        } else if message.hasPrefix("AUTHREQ_ATTRIBUTION") {
            let (accessingRef, requestingRef) = parseAuthreqAttribution(message)
            accessing = accessingRef
            requesting = requestingRef
        } else if message.hasPrefix("AUTHREQ_RESULT") {
            if let (value, reason) = parseAuthreqResult(message) {
                authValue = value
                authReason = reason
            }
        }
    }

    guard let service else { return nil }
    return TCCEvent(
        timestamp: earliest,
        msgID: msgID,
        service: service,
        isPreflight: isPreflight,
        accessingProcess: accessing,
        requestingProcess: requesting,
        outcome: authValue.map(TCCOutcome.from(authValue:)) ?? .unknown(rawValue: -1),
        authValueRaw: authValue ?? -1,
        authReasonRaw: authReason ?? -1
    )
}

// MARK: - Line shape parsers

/// Extract the `msgID=...` value from any TCC message line. tccd uses
/// the same `<tccd_pid>.<sequence>` form across every line of a
/// transaction.
internal func extractMsgID(from message: String) -> String? {
    capture(message, pattern: #"msgID=([0-9.]+)"#)
}

/// Parse `AUTHREQ_CTX: msgID=..., function=..., service=..., preflight=yes, query=...`.
/// Returns the service and the preflight bit.
internal func parseAuthreqCTX(_ message: String) -> (TCCService, Bool)? {
    guard let serviceRaw = capture(message, pattern: #"service=([A-Za-z0-9]+)"#) else {
        return nil
    }
    let preflight = capture(message, pattern: #"preflight=(yes|no)"#) == "yes"
    return (TCCService.from(rawValue: serviceRaw), preflight)
}

/// Parse `AUTHREQ_ATTRIBUTION: msgID=..., attribution={accessing={TCCDProcess:
/// identifier=..., pid=..., auid=..., euid=..., binary_path=...}, requesting={...}}`.
/// Returns the (accessing, requesting) pair; either may be `nil` if
/// the corresponding block didn't parse.
internal func parseAuthreqAttribution(_ message: String) -> (TCCProcessRef?, TCCProcessRef?) {
    let accessing = extractProcessRef(role: "accessing", from: message)
    let requesting = extractProcessRef(role: "requesting", from: message)
    return (accessing, requesting)
}

/// Parse `AUTHREQ_RESULT: msgID=..., authValue=N, authReason=N, ...`.
internal func parseAuthreqResult(_ message: String) -> (Int, Int)? {
    guard
        let valueText = capture(message, pattern: #"authValue=(-?[0-9]+)"#),
        let value = Int(valueText)
    else { return nil }
    let reasonText = capture(message, pattern: #"authReason=(-?[0-9]+)"#)
    let reason = reasonText.flatMap(Int.init) ?? 0
    return (value, reason)
}

/// Extract a single `TCCProcessRef` matching the requested role. The
/// `AUTHREQ_ATTRIBUTION` line wraps each ref in
/// `<role>={TCCDProcess: identifier=..., pid=..., auid=..., euid=...,
/// binary_path=...}` — we pluck the inner field set by name.
private func extractProcessRef(role: String, from message: String) -> TCCProcessRef? {
    // Find the role block via balanced-brace-tolerant pattern. Greedy
    // up to the next `}, ` keeps us out of nested braces.
    let pattern = #"\#(role)=\{TCCDProcess:([^}]+)\}"#
    guard let block = capture(message, pattern: pattern) else { return nil }

    guard let identifier = capture(block, pattern: #"identifier=([^,]+)"#) else { return nil }
    guard
        let pidText = capture(block, pattern: #"pid=(-?[0-9]+)"#),
        let pid = Int32(pidText)
    else { return nil }
    let auidText = capture(block, pattern: #"auid=(-?[0-9]+)"#) ?? "0"
    let euidText = capture(block, pattern: #"euid=(-?[0-9]+)"#) ?? "0"
    let binaryPath = capture(block, pattern: #"binary_path=(.+)$"#)?
        .trimmingCharacters(in: .whitespaces) ?? ""

    return TCCProcessRef(
        identifier: identifier.trimmingCharacters(in: .whitespaces),
        pid: pid_t(pid),
        auid: uid_t(truncatingIfNeeded: Int(auidText) ?? 0),
        euid: uid_t(truncatingIfNeeded: Int(euidText) ?? 0),
        binaryPath: binaryPath
    )
}

/// Run a regex with one capture group; return the captured substring,
/// or `nil` if the pattern didn't match.
private func capture(_ source: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(source.startIndex..<source.endIndex, in: source)
    guard
        let match = regex.firstMatch(in: source, range: range),
        match.numberOfRanges >= 2,
        let captureRange = Range(match.range(at: 1), in: source)
    else { return nil }
    return String(source[captureRange])
}
