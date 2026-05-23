import ArgumentParser
import Darwin
import Foundation
import OWPersistence

struct WatchPersistenceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch-persistence",
        abstract: "Live-tail filesystem mutations across every persistence-relevant location.",
        discussion: """
            Subscribes to FSEvents on Owlwatch's standard persistence \
            watch set (LaunchAgents/Daemons in /System/Library, /Library, \
            and ~/Library; the System Extensions registry; kext bundles; \
            the loginwindow preference plists) and prints one row per \
            mutation as it happens.

            The complement to `owlwatch persistence` (snapshot) and \
            `owlwatch login-items` (BTM dump). Where those answer "what's \
            installed right now?", this answers "what just changed?". \
            Runs until interrupted with Ctrl-C.

            Output columns: TIMESTAMP, KIND, SCOPE, PATH.

            Examples:
              owlwatch watch-persistence
              owlwatch watch-persistence --scope user-launchd
              owlwatch watch-persistence --kind added,removed
        """
    )

    @Option(
        name: .long,
        help: """
            Comma-separated mutation kinds: added, modified, removed, \
            renamed, xattr-changed, metadata-changed.
            """
    )
    var kind: String?

    @Option(
        name: .long,
        help: """
            Filter to one scope: platform-launchd | system-launchd | \
            user-launchd | system-extensions-registry | \
            kernel-extensions | loginwindow-plist.
            """
    )
    var scope: String?

    @Option(
        name: .long,
        help: "FSEvents coalescing latency in seconds. 0.0 = emit immediately."
    )
    var latency: Double?

    @Flag(
        name: .long,
        help: """
            Skip parsing the changed plist; show only raw mutation \
            fields (timestamp, kind, scope, path).
            """
    )
    var raw: Bool = false

    func run() async throws {
        let allowedKinds = parseKindList(kind)
        let allowedScope = parseScope(scope)
        let latencyValue = latency ?? 0.5

        if raw {
            try await runRaw(allowedKinds: allowedKinds, allowedScope: allowedScope, latency: latencyValue)
        } else {
            try await runEnriched(allowedKinds: allowedKinds, allowedScope: allowedScope, latency: latencyValue)
        }
    }

    private func runRaw(
        allowedKinds: Set<MutationKind>?,
        allowedScope: MutationScope?,
        latency: TimeInterval
    ) async throws {
        let header = ["TIMESTAMP", "KIND", "SCOPE", "PATH"]
        let widths = [12, 17, 25, 80]
        print(formatRow(header, widths: widths))
        fflush(stdout)
        for try await mutation in OWPersistence.monitor(latency: latency) {
            if let allowedKinds, !allowedKinds.contains(mutation.kind) { continue }
            if let allowedScope, mutation.scope != allowedScope { continue }
            print(formatRow(renderRawRow(mutation), widths: widths))
            fflush(stdout)
        }
    }

    private func runEnriched(
        allowedKinds: Set<MutationKind>?,
        allowedScope: MutationScope?,
        latency: TimeInterval
    ) async throws {
        let header = ["TIMESTAMP", "KIND", "SCOPE", "LABEL / HOOK", "PROGRAM / SCRIPT", "PATH"]
        let widths = [12, 17, 18, 40, 50, 60]
        print(formatRow(header, widths: widths))
        fflush(stdout)
        for try await enriched in OWPersistence.monitorEnriched(latency: latency) {
            let mutation = enriched.mutation
            if let allowedKinds, !allowedKinds.contains(mutation.kind) { continue }
            if let allowedScope, mutation.scope != allowedScope { continue }
            print(formatRow(renderEnrichedRow(enriched), widths: widths))
            fflush(stdout)
        }
    }

    // MARK: - Argument parsing

    private func parseKindList(_ string: String?) -> Set<MutationKind>? {
        guard let string, !string.isEmpty else { return nil }
        var result: Set<MutationKind> = []
        for token in string.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if let kind = parseKind(token) {
                result.insert(kind)
            }
        }
        return result.isEmpty ? nil : result
    }

    private func parseKind(_ string: String) -> MutationKind? {
        switch string {
        case "added": return .added
        case "modified": return .modified
        case "removed": return .removed
        case "renamed": return .renamed
        case "xattr-changed": return .xattrChanged
        case "metadata-changed": return .metadataChanged
        default: return nil
        }
    }

    private func parseScope(_ string: String?) -> MutationScope? {
        switch string {
        case "platform-launchd": return .platformLaunchd
        case "system-launchd": return .systemLaunchd
        case "user-launchd": return .userLaunchd
        case "system-extensions-registry": return .systemExtensionsRegistry
        case "kernel-extensions": return .kernelExtensions
        case "loginwindow-plist": return .loginwindowPlist
        default: return nil
        }
    }

    // MARK: - Rendering

    private func renderRawRow(_ mutation: PersistenceMutation) -> [String] {
        [
            renderTimestamp(mutation.timestamp),
            renderKind(mutation.kind),
            renderScope(mutation.scope),
            mutation.path
        ]
    }

    private func renderEnrichedRow(_ enriched: EnrichedMutation) -> [String] {
        let mutation = enriched.mutation
        let (label, program) = renderPayload(enriched)
        return [
            renderTimestamp(mutation.timestamp),
            renderKind(mutation.kind),
            renderScope(mutation.scope),
            label,
            program,
            mutation.path
        ]
    }

    /// Pull the two most-detection-relevant fields out of the
    /// enriched payload — Label and Program for launchd services,
    /// Kind and Script for login/logout hooks. `("-", "-")` when
    /// nothing parsed (removal, parse failure, unsupported scope).
    private func renderPayload(_ enriched: EnrichedMutation) -> (String, String) {
        if let service = enriched.launchService {
            return (service.label ?? "(no Label)", service.executablePath ?? "(no Program)")
        }
        if let hooks = enriched.hooks, !hooks.isEmpty {
            let kinds = hooks.map(\.kind.rawValue).joined(separator: ",")
            let scripts = hooks.map(\.scriptPath).joined(separator: " | ")
            return (kinds, scripts)
        }
        return ("-", "-")
    }

    private func renderTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private func renderKind(_ kind: MutationKind) -> String {
        switch kind {
        case .added: return "ADDED"
        case .modified: return "modified"
        case .removed: return "REMOVED"
        case .renamed: return "renamed"
        case .xattrChanged: return "xattr-changed"
        case .metadataChanged: return "metadata-changed"
        }
    }

    private func renderScope(_ scope: MutationScope) -> String {
        switch scope {
        case .platformLaunchd: return "platform-launchd"
        case .systemLaunchd: return "system-launchd"
        case .userLaunchd: return "user-launchd"
        case .systemExtensionsRegistry: return "sysext-registry"
        case .kernelExtensions: return "kernel-extensions"
        case .loginwindowPlist: return "loginwindow-plist"
        case .other: return "other"
        }
    }

    private func formatRow(_ cells: [String], widths: [Int]) -> String {
        cells.enumerated()
            .map { index, cell in cell.padding(toLength: widths[index], withPad: " ", startingAt: 0) }
            .joined(separator: "  ")
            .trimmingCharacters(in: .whitespaces)
    }
}
