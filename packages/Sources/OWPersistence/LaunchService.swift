import Foundation

/// A `launchd`-managed persistence item — a Launch Daemon or Launch Agent.
///
/// Lives as a `.plist` on disk in one of five well-known locations:
///
/// | Scope | Path | Runs as |
/// |---|---|---|
/// | ``LaunchScope/platformDaemon`` | `/System/Library/LaunchDaemons` | root, system-wide |
/// | ``LaunchScope/platformAgent`` | `/System/Library/LaunchAgents` | logged-in user, per-session |
/// | ``LaunchScope/systemDaemon`` | `/Library/LaunchDaemons` | root, system-wide |
/// | ``LaunchScope/systemAgent`` | `/Library/LaunchAgents` | logged-in user, per-session |
/// | ``LaunchScope/userAgent`` | `~/Library/LaunchAgents` | the owning user, per-session |
///
/// For an EDR, the malware-relevant facts are: *what binary runs*
/// (``executablePath`` + ``arguments``), *under what triggers*
/// (``runAtLoad``, ``keepAlive``, ``watchPaths``, ``startInterval``),
/// and *is it currently active* (``isDisabled``). Tampered plists
/// pointing at unexpected binaries are tier-1 detection signal.
public struct LaunchService: Sendable, Equatable, Hashable {
    /// Path to the `.plist` file on disk.
    public let plistPath: String

    /// Scope this plist lives in.
    public let scope: LaunchScope

    /// `Label` key from the plist — `launchd`'s unique identifier. Usually
    /// reverse-DNS (`com.apple.dock.agent`, `com.knollsoft.Rectangle`).
    /// If the plist is missing a Label key the value is `nil` (malformed
    /// but enumerable).
    public let label: String?

    /// Resolved executable path. `Program` key if set, else
    /// `ProgramArguments[0]`. Symbolic links not resolved — the value is
    /// the literal string the plist specifies, so detection rules can
    /// match on it.
    public let executablePath: String?

    /// `ProgramArguments[1...]`. Empty if the plist uses `Program` (which
    /// takes no arguments) or has only the executable in
    /// `ProgramArguments`.
    public let arguments: [String]

    /// `RunAtLoad` key. `true` means `launchd` starts the service as
    /// soon as the plist is loaded. The single most common malware
    /// persistence trigger.
    public let runAtLoad: Bool

    /// `KeepAlive` key — either an unconditional `true` / `false`
    /// (``KeepAlive/always(_:)``) or a dict of conditions
    /// (``KeepAlive/conditional(_:)``). When set to `true` the service
    /// is respawned immediately if it exits, which is a malware
    /// recovery / anti-removal signal.
    public let keepAlive: KeepAlive

    /// `WatchPaths` key. Filesystem paths whose modification triggers
    /// `launchd` to start the service. Common in malware that wants to
    /// react to user activity or to a dropped trigger file.
    public let watchPaths: [String]

    /// `StartInterval` key (seconds). When set, `launchd` runs the
    /// service every N seconds — cron-without-cron. `nil` if unset.
    public let startInterval: TimeInterval?

    /// `StartCalendarInterval` key. A scheduled run at a specific
    /// minute / hour / day / weekday / month. The plist permits either
    /// a single dict or an array of dicts; both are flattened here.
    public let startCalendarInterval: [CalendarInterval]

    /// Final disabled status — `true` if either the plist's own
    /// `Disabled` key is `true` *or* the central
    /// `/var/db/com.apple.xpc.launchd/disabled*.plist` says so. The
    /// central file takes precedence when both are set, but if the
    /// service appears as disabled in either, we report it.
    public let isDisabled: Bool

    public init(
        plistPath: String,
        scope: LaunchScope,
        label: String?,
        executablePath: String?,
        arguments: [String],
        runAtLoad: Bool,
        keepAlive: KeepAlive,
        watchPaths: [String],
        startInterval: TimeInterval?,
        startCalendarInterval: [CalendarInterval],
        isDisabled: Bool
    ) {
        self.plistPath = plistPath
        self.scope = scope
        self.label = label
        self.executablePath = executablePath
        self.arguments = arguments
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.watchPaths = watchPaths
        self.startInterval = startInterval
        self.startCalendarInterval = startCalendarInterval
        self.isDisabled = isDisabled
    }
}

/// Where a launchd plist lives. Used by callers to filter by trust
/// level (Apple-shipped under `/System` vs third-party under `/Library`
/// vs per-user under `~`) and by privilege (daemons run as root;
/// agents run as the user).
public enum LaunchScope: String, Sendable, Equatable, Hashable, CaseIterable {
    /// `/System/Library/LaunchDaemons` — Apple-shipped, runs as root.
    /// SIP-protected; the contents cannot be modified by ordinary
    /// processes.
    case platformDaemon

    /// `/System/Library/LaunchAgents` — Apple-shipped, runs as the
    /// logged-in user. SIP-protected.
    case platformAgent

    /// `/Library/LaunchDaemons` — third-party / admin-installed,
    /// runs as root. Writing here requires admin authentication.
    case systemDaemon

    /// `/Library/LaunchAgents` — third-party / admin-installed, runs
    /// as the logged-in user. Writing requires admin authentication.
    case systemAgent

    /// `~/Library/LaunchAgents` — per-user, runs as that user. Writing
    /// requires no elevation. By far the most common malware
    /// persistence location on macOS.
    case userAgent

    /// `true` for daemons (run as root) — both platform and system
    /// scopes. Useful for "is this a privileged persistence item?"
    /// detection rules.
    public var runsAsRoot: Bool {
        self == .platformDaemon || self == .systemDaemon
    }

    /// Filesystem path the scope corresponds to. `~` is expanded to the
    /// current user's home for ``userAgent``.
    public var directoryPath: String {
        switch self {
        case .platformDaemon: return "/System/Library/LaunchDaemons"
        case .platformAgent: return "/System/Library/LaunchAgents"
        case .systemDaemon: return "/Library/LaunchDaemons"
        case .systemAgent: return "/Library/LaunchAgents"
        case .userAgent:
            return (NSHomeDirectory() as NSString).appendingPathComponent("Library/LaunchAgents")
        }
    }
}

/// `KeepAlive` value, which the plist can express as either a boolean
/// or a dictionary of conditions.
public enum KeepAlive: Sendable, Equatable, Hashable {
    /// Unconditional — `true` means "always keep alive", `false` means
    /// "never". `false` is also the default when the key is absent.
    case always(Bool)

    /// Conditional — keep alive only when these conditions hold.
    case conditional(KeepAliveConditions)

    /// `true` if the service will be restarted under any condition.
    /// `false` only for ``always(false)`` and for ``conditional`` with
    /// no flags set.
    public var isActive: Bool {
        switch self {
        case .always(let value): return value
        case .conditional(let conditions): return conditions.hasAnyCondition
        }
    }
}

/// Conditions under which a `KeepAlive` dict triggers a restart.
/// Mirrors the documented `launchd.plist(5)` keys. Each field is
/// `nil` when the corresponding key is absent.
public struct KeepAliveConditions: Sendable, Equatable, Hashable {
    /// `AfterInitialDemand` — wait until the service is requested
    /// once before applying keep-alive.
    public let afterInitialDemand: Bool?

    /// `SuccessfulExit` — `true` means "restart only after success",
    /// `false` means "restart only after failure".
    public let successfulExit: Bool?

    /// `NetworkState` — restart when network connectivity matches.
    public let networkState: Bool?

    /// `Crashed` — restart specifically after a crash.
    public let crashed: Bool?

    /// `PathState` — map of path → whether the path's existence
    /// triggers the restart.
    public let pathState: [String: Bool]

    /// `OtherJobEnabled` — map of other launchd job label → whether
    /// that job's enabled state triggers the restart.
    public let otherJobEnabled: [String: Bool]

    /// `true` if any of the conditions is non-nil / non-empty.
    public var hasAnyCondition: Bool {
        afterInitialDemand != nil
            || successfulExit != nil
            || networkState != nil
            || crashed != nil
            || !pathState.isEmpty
            || !otherJobEnabled.isEmpty
    }
}

/// A single `StartCalendarInterval` entry — a `launchd` "run at this
/// time" trigger. Any field `nil` is treated by `launchd` as
/// "wildcard" for that component (e.g. `minute: 0, hour: 9` runs
/// every day at 9:00).
public struct CalendarInterval: Sendable, Equatable, Hashable {
    public let minute: Int?
    public let hour: Int?
    public let day: Int?
    public let weekday: Int?
    public let month: Int?

    public init(minute: Int? = nil, hour: Int? = nil, day: Int? = nil, weekday: Int? = nil, month: Int? = nil) {
        self.minute = minute
        self.hour = hour
        self.day = day
        self.weekday = weekday
        self.month = month
    }
}

/// Errors thrown by ``OWPersistence/OWPersistence``.
public enum OWPersistenceError: Error, Sendable, Equatable {
    /// Couldn't read the directory the scope refers to. `errno` is the
    /// underlying POSIX error if available.
    case scopeUnreadable(scope: LaunchScope, errno: Int32)
}
