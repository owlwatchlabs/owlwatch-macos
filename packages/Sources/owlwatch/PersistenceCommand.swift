import ArgumentParser
import Foundation
import OWPersistence

struct PersistenceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "persistence",
        abstract: "List installed auto-start items (LaunchAgents, LaunchDaemons).",
        discussion: """
            Enumerates every launchd-managed Launch Daemon and Launch Agent \
            visible to the caller, across the five standard locations: \
            /System/Library/LaunchDaemons, /System/Library/LaunchAgents, \
            /Library/LaunchDaemons, /Library/LaunchAgents, and \
            ~/Library/LaunchAgents.

            Default output is one row per service with scope, label, the \
            binary the service runs, current disabled state, and a compact \
            triggers summary. M5.2 will add login items and system \
            extensions; M5.3 will add kernel extensions, cron jobs, and \
            login/logout hooks.

            Examples:
              owlwatch persistence
              owlwatch persistence --user-only
              owlwatch persistence --enabled-only
              owlwatch persistence --scope system-daemon
            """
    )

    @Flag(name: .long, help: "Only show third-party items (skip /System/Library platform plists).")
    var thirdPartyOnly: Bool = false

    @Flag(name: .long, help: "Only show items in ~/Library/LaunchAgents.")
    var userOnly: Bool = false

    @Flag(name: .long, help: "Only show currently-enabled items.")
    var enabledOnly: Bool = false

    @Option(
        name: .long,
        help: "Filter to one scope: platform-daemon | platform-agent | system-daemon | system-agent | user-agent."
    )
    var scope: String?

    func run() throws {
        let services = OWPersistence.launchServices()
        let filtered = applyFilters(to: services)
        printTable(services: filtered)
    }

    private func applyFilters(to services: [LaunchService]) -> [LaunchService] {
        services.filter { service in
            if thirdPartyOnly {
                if service.scope == .platformDaemon || service.scope == .platformAgent {
                    return false
                }
            }
            if userOnly && service.scope != .userAgent { return false }
            if enabledOnly && service.isDisabled { return false }
            if let scope, parseScope(scope) != service.scope { return false }
            return true
        }
    }

    private func parseScope(_ string: String) -> LaunchScope? {
        switch string {
        case "platform-daemon": return .platformDaemon
        case "platform-agent": return .platformAgent
        case "system-daemon": return .systemDaemon
        case "system-agent": return .systemAgent
        case "user-agent": return .userAgent
        default: return nil
        }
    }

    private func printTable(services: [LaunchService]) {
        let sorted = services.sorted { lhs, rhs in
            if lhs.scope != rhs.scope { return lhs.scope.rawValue < rhs.scope.rawValue }
            return (lhs.label ?? "") < (rhs.label ?? "")
        }
        let rows = sorted.map(renderRow)
        let header = ["SCOPE", "LABEL", "PROGRAM", "STATE", "TRIGGERS"]
        let widths = columnWidths(header: header, rows: rows)
        print(formatRow(header, widths: widths))
        for row in rows {
            print(formatRow(row, widths: widths))
        }
    }

    private func renderRow(_ service: LaunchService) -> [String] {
        let scope = renderScope(service.scope)
        let label = service.label ?? "(no Label)"
        let program = service.executablePath ?? "(no Program)"
        let state = service.isDisabled ? "disabled" : "enabled"
        let triggers = renderTriggers(service)
        return [scope, label, program, state, triggers]
    }

    private func renderScope(_ scope: LaunchScope) -> String {
        switch scope {
        case .platformDaemon: return "platform-daemon"
        case .platformAgent: return "platform-agent"
        case .systemDaemon: return "system-daemon"
        case .systemAgent: return "system-agent"
        case .userAgent: return "user-agent"
        }
    }

    private func renderTriggers(_ service: LaunchService) -> String {
        var parts: [String] = []
        if service.runAtLoad { parts.append("run-at-load") }
        if service.keepAlive.isActive { parts.append("keep-alive") }
        if !service.watchPaths.isEmpty { parts.append("watch-paths(\(service.watchPaths.count))") }
        if service.startInterval != nil { parts.append("interval") }
        if !service.startCalendarInterval.isEmpty { parts.append("calendar(\(service.startCalendarInterval.count))") }
        return parts.isEmpty ? "-" : parts.joined(separator: " ")
    }

    private func columnWidths(header: [String], rows: [[String]]) -> [Int] {
        var widths = header.map { $0.count }
        for row in rows {
            for (index, cell) in row.enumerated() where index < widths.count {
                widths[index] = max(widths[index], cell.count)
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
