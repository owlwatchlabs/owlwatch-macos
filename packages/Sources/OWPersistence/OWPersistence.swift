import Darwin
import Foundation

/// Enumerates macOS persistence — the auto-start, auto-respawn,
/// auto-trigger items that survive reboot and login.
///
/// M5.1 covers `launchd`-managed services: Launch Daemons and Launch
/// Agents in the five standard locations (system platform under
/// `/System/Library`, third-party under `/Library`, per-user under
/// `~/Library`). Future slices add login items (M5.2), system extensions
/// (M5.2), kernel extensions (M5.3), cron, and login/logout hooks (M5.3).
///
/// `OWPersistence` is a snapshot library, same posture as `OWNetwork`
/// and `OWProcess`. For real-time *new persistence-item installed*
/// detection, M10's persistence monitor (FSEvents-backed) is the right
/// tool. M5 answers point-in-time questions: "what's set to auto-start
/// on this box right now?", "which agents am I currently allowing?",
/// "is there an unexpected daemon in `/Library/LaunchDaemons`?".
public enum OWPersistence {
    /// Capture every Launch Daemon and Launch Agent visible to the
    /// caller, across all five standard scopes.
    ///
    /// Scopes the caller can't read are silently skipped — matches
    /// `launchctl print-disabled`'s posture of partial visibility.
    public static func launchServices() -> [LaunchService] {
        var services: [LaunchService] = []
        for scope in LaunchScope.allCases {
            services.append(contentsOf: launchServices(in: scope))
        }
        return services
    }

    /// Capture every Background Task Management (BTM) record visible
    /// to the caller — apps with login behavior, SMAppService-registered
    /// agents and daemons, Spotlight importers, QuickLook extensions,
    /// legacy login items.
    ///
    /// Implementation note: the BTM database under
    /// `/var/db/com.apple.backgroundtaskmanagementagent/` is not readable
    /// by ordinary users, so this method shells to Apple's
    /// `/usr/bin/sfltool dumpbtm` and parses its structured-text output.
    /// The format is not contractually stable across macOS versions;
    /// unrecognized types land in ``LoginItemKind/other(rawName:)`` with
    /// the raw text preserved so detection rules can still match on them.
    ///
    /// Returns an empty array if `sfltool` is missing, fails to run,
    /// or produces no parseable records.
    public static func loginItems() -> [LoginItem] {
        parseSfltoolDumpbtm(runSfltoolDumpbtm())
    }

    /// Capture every registered System Extension (DriverKit drivers,
    /// Network Extensions, Endpoint Security clients) from
    /// `/Library/SystemExtensions/db.plist`.
    ///
    /// The registry is world-readable; no entitlements required.
    /// Returns an empty array when the file is absent (no extensions
    /// have ever been activated on this system) or unparseable.
    public static func systemExtensions() -> [SystemExtension] {
        parseSystemExtensionDB(at: "/Library/SystemExtensions/db.plist")
    }

    /// Capture every Kernel Extension bundle on disk, across both
    /// scopes (`/System/Library/Extensions` and `/Library/Extensions`).
    ///
    /// Static inspection of the bundles' `Info.plist`. Does NOT report
    /// runtime loaded-status (`kextstat` territory) — that's deferred
    /// to M10's persistence monitor where a runtime-aware view makes
    /// sense.
    public static func kernelExtensions() -> [KernelExtension] {
        var extensions: [KernelExtension] = []
        for scope in KernelExtensionScope.allCases {
            extensions.append(contentsOf: kernelExtensions(in: scope))
        }
        return extensions
    }

    /// Capture kernel extensions from a single scope.
    public static func kernelExtensions(in scope: KernelExtensionScope) -> [KernelExtension] {
        let bundlePaths = enumerateKextBundles(in: scope.directoryPath)
        return bundlePaths.compactMap { parseKernelExtension(at: $0, scope: scope) }
    }

    /// Capture launch services from a single scope.
    public static func launchServices(in scope: LaunchScope) -> [LaunchService] {
        let directory = scope.directoryPath
        let plistPaths = enumeratePlists(in: directory)
        let disabledMap = readCentralDisabledList(for: scope)

        var services: [LaunchService] = []
        services.reserveCapacity(plistPaths.count)
        for plistPath in plistPaths {
            if let service = parseLaunchService(at: plistPath, scope: scope, centralDisabledMap: disabledMap) {
                services.append(service)
            }
        }
        return services
    }
}

// MARK: - Directory traversal

private func enumeratePlists(in directory: String) -> [String] {
    let fileManager = FileManager.default
    guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else {
        return []
    }
    return entries
        .filter { $0.hasSuffix(".plist") && !$0.hasPrefix(".") }
        .map { (directory as NSString).appendingPathComponent($0) }
        .sorted()
}

// MARK: - Central disabled-list resolution

private func readCentralDisabledList(for scope: LaunchScope) -> [String: Bool] {
    let path = centralDisabledListPath(for: scope)
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [:] }
    guard let parsed = try? PropertyListSerialization.propertyList(
        from: data, options: [], format: nil
    ) as? [String: Bool] else { return [:] }
    return parsed
}

private func centralDisabledListPath(for scope: LaunchScope) -> String {
    switch scope {
    case .platformDaemon, .systemDaemon:
        return "/var/db/com.apple.xpc.launchd/disabled.plist"
    case .platformAgent, .systemAgent, .userAgent:
        return "/var/db/com.apple.xpc.launchd/disabled.\(getuid()).plist"
    }
}

// MARK: - Plist parsing

internal func parseLaunchService(
    at plistPath: String,
    scope: LaunchScope,
    centralDisabledMap: [String: Bool]
) -> LaunchService? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: plistPath)) else { return nil }
    guard let plist = try? PropertyListSerialization.propertyList(
        from: data, options: [], format: nil
    ) as? [String: Any] else { return nil }

    let label = plist["Label"] as? String
    let (executablePath, arguments) = extractProgram(from: plist)
    let runAtLoad = plist["RunAtLoad"] as? Bool ?? false
    let keepAlive = extractKeepAlive(from: plist["KeepAlive"])
    let watchPaths = plist["WatchPaths"] as? [String] ?? []
    let startInterval = (plist["StartInterval"] as? NSNumber).map { TimeInterval(truncating: $0) }
    let startCalendarInterval = extractCalendarIntervals(from: plist["StartCalendarInterval"])
    let inPlistDisabled = plist["Disabled"] as? Bool ?? false
    let centrallyDisabled = label.flatMap { centralDisabledMap[$0] } ?? false
    let isDisabled = inPlistDisabled || centrallyDisabled

    return LaunchService(
        plistPath: plistPath,
        scope: scope,
        label: label,
        executablePath: executablePath,
        arguments: arguments,
        runAtLoad: runAtLoad,
        keepAlive: keepAlive,
        watchPaths: watchPaths,
        startInterval: startInterval,
        startCalendarInterval: startCalendarInterval,
        isDisabled: isDisabled
    )
}

internal func extractProgram(from plist: [String: Any]) -> (executablePath: String?, arguments: [String]) {
    if let program = plist["Program"] as? String {
        let extra = (plist["ProgramArguments"] as? [String]) ?? []
        // When both are present, ProgramArguments is argv including argv[0]
        // and Program is the actual binary path. argv[0] is typically a
        // logical name, not the binary — keep Program as the executable
        // and take ProgramArguments[1...] as arguments.
        let args = extra.isEmpty ? [] : Array(extra.dropFirst())
        return (program, args)
    }
    if let programArguments = plist["ProgramArguments"] as? [String], !programArguments.isEmpty {
        return (programArguments[0], Array(programArguments.dropFirst()))
    }
    return (nil, [])
}

internal func extractKeepAlive(from value: Any?) -> KeepAlive {
    guard let value else { return .always(false) }
    if let bool = value as? Bool {
        return .always(bool)
    }
    if let dict = value as? [String: Any] {
        return .conditional(KeepAliveConditions(
            afterInitialDemand: dict["AfterInitialDemand"] as? Bool,
            successfulExit: dict["SuccessfulExit"] as? Bool,
            networkState: dict["NetworkState"] as? Bool,
            crashed: dict["Crashed"] as? Bool,
            pathState: (dict["PathState"] as? [String: Bool]) ?? [:],
            otherJobEnabled: (dict["OtherJobEnabled"] as? [String: Bool]) ?? [:]
        ))
    }
    return .always(false)
}

internal func extractCalendarIntervals(from value: Any?) -> [CalendarInterval] {
    if let dict = value as? [String: Any] {
        return [calendarIntervalFromDict(dict)]
    }
    if let array = value as? [[String: Any]] {
        return array.map(calendarIntervalFromDict)
    }
    return []
}

private func calendarIntervalFromDict(_ dict: [String: Any]) -> CalendarInterval {
    CalendarInterval(
        minute: dict["Minute"] as? Int,
        hour: dict["Hour"] as? Int,
        day: dict["Day"] as? Int,
        weekday: dict["Weekday"] as? Int,
        month: dict["Month"] as? Int
    )
}
