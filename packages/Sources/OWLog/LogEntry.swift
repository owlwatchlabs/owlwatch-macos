import Darwin
import Foundation

/// A single record from macOS's unified logging archive (`os_log`).
///
/// Fields mirror the subset of `log show --style ndjson` output that
/// matters for detection — timestamp, the originating process,
/// subsystem + category, level, the rendered message. The verbose
/// internal fields (backtrace frames, image UUIDs, trace IDs, raw
/// format strings) are intentionally dropped: they're useful for
/// kernel debugging but not for "what happened?" queries.
///
/// For an EDR, the high-value subsystems are:
///
/// - `com.apple.TCC` — privacy-permission requests and grants
/// - `com.apple.SecurityServer` — code signing decisions, Keychain
///   unlocks
/// - `com.apple.LaunchServices` — app launches and bundle
///   registrations
/// - `com.apple.spctl` — Gatekeeper assessments
/// - `com.apple.endpoint-security` — ES client lifecycle
public struct LogEntry: Sendable, Equatable, Hashable {
    /// Decoded timestamp from the record's `timestamp` field.
    public let timestamp: Date

    /// Process binary basename (last path component of
    /// ``processPath``). `nil` when the record didn't include a
    /// process image path — rare; typically Mach traps and a few
    /// kernel-side messages.
    public let processName: String?

    /// `processImagePath` from the record — full path to the
    /// originating binary.
    public let processPath: String?

    /// `processID` from the record. `nil` for messages emitted before
    /// the process table was set up (very early-boot kernel messages).
    public let processID: pid_t?

    /// `userID` from the record (POSIX uid the process was running
    /// as). `nil` when the record didn't carry one.
    public let userID: uid_t?

    /// `threadID` from the record — kernel thread identifier, not a
    /// Mach port. `nil` if absent.
    public let threadID: UInt64?

    /// `subsystem` field — reverse-DNS string declared by the
    /// emitting framework / app (`com.apple.TCC`, etc.). `nil` for
    /// messages emitted without a subsystem (most `printf`-style
    /// legacy logging).
    public let subsystem: String?

    /// `category` field — secondary classifier within the subsystem
    /// (e.g. `access` under `com.apple.TCC`). `nil` when absent.
    public let category: String?

    /// `messageType` mapped to the typed enum. See ``LogLevel``.
    public let level: LogLevel

    /// `eventType` mapped to the typed enum. See ``LogEventType``.
    public let eventType: LogEventType

    /// `eventMessage` — the rendered message text.
    public let message: String

    /// `activityIdentifier` field. `0` means "no activity scope". Used
    /// to correlate related log entries that share an `os_activity`.
    public let activityID: UInt64

    public init(
        timestamp: Date,
        processName: String?,
        processPath: String?,
        processID: pid_t?,
        userID: uid_t?,
        threadID: UInt64?,
        subsystem: String?,
        category: String?,
        level: LogLevel,
        eventType: LogEventType,
        message: String,
        activityID: UInt64
    ) {
        self.timestamp = timestamp
        self.processName = processName
        self.processPath = processPath
        self.processID = processID
        self.userID = userID
        self.threadID = threadID
        self.subsystem = subsystem
        self.category = category
        self.level = level
        self.eventType = eventType
        self.message = message
        self.activityID = activityID
    }
}

/// `os_log` message-type / severity. Mirrors `OSLogEntryLog.Level` and
/// the `messageType` strings `log show` produces.
public enum LogLevel: String, Sendable, Equatable, Hashable, CaseIterable {
    /// "Default" — normal log message.
    case `default`

    /// "Info" — informational, typically excluded unless `--info` is
    /// set on `log show`.
    case info

    /// "Debug" — developer debugging, excluded unless `--debug` is set.
    case debug

    /// "Error" — error condition. Always included regardless of
    /// info/debug flags.
    case error

    /// "Fault" — programmer error / unrecoverable. Always included.
    case fault

    /// Map from the `messageType` string `log show` produces.
    /// Anything unrecognized falls back to ``default``.
    static func from(rawValue: String) -> LogLevel {
        switch rawValue {
        case "Default": return .default
        case "Info": return .info
        case "Debug": return .debug
        case "Error": return .error
        case "Fault": return .fault
        default: return .default
        }
    }
}

/// `os_log` event type. Most entries are ``log`` messages; the others
/// surface activity boundaries, signposts, and state-transition events
/// that detection rules occasionally need to filter on.
public enum LogEventType: Sendable, Equatable, Hashable {
    /// `logEvent` — a regular log message.
    case log

    /// `stateEvent` — an `os_state_add_handler` state-callback result.
    case state

    /// `userActionEvent` — user-initiated action (clicks, key presses)
    /// surfaced through the input subsystem.
    case userAction

    /// `signpostEvent` — `os_signpost` boundary marker (begin/end of
    /// a measured interval).
    case signpost

    /// `traceEvent` — kernel-side trace data.
    case trace

    /// Any value `log show` produces that we don't recognize. Raw
    /// string preserved so detection rules can still match on it.
    case other(rawValue: String)

    /// String value as it appears in `log show` output.
    public var rawValue: String {
        switch self {
        case .log: return "logEvent"
        case .state: return "stateEvent"
        case .userAction: return "userActionEvent"
        case .signpost: return "signpostEvent"
        case .trace: return "traceEvent"
        case .other(let raw): return raw
        }
    }

    static func from(rawValue: String) -> LogEventType {
        switch rawValue {
        case "logEvent": return .log
        case "stateEvent": return .state
        case "userActionEvent": return .userAction
        case "signpostEvent": return .signpost
        case "traceEvent": return .trace
        default: return .other(rawValue: rawValue)
        }
    }
}
