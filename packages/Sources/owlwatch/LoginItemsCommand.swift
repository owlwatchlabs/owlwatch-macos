import ArgumentParser
import Darwin
import Foundation
import OWPersistence

struct LoginItemsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "login-items",
        abstract: "List Background Task Management (BTM) records — login items, helper agents, extensions.",
        discussion: """
            Enumerates every BTM record visible to the caller — apps with \
            login behavior, SMAppService-registered agents and daemons, \
            Spotlight importers, QuickLook extensions, and legacy login \
            items. The underlying BTM database is system-protected; this \
            subcommand shells to /usr/bin/sfltool dumpbtm and parses its \
            output, so what you see matches `sfltool dumpbtm` (modulo \
            formatting).

            Output columns: UID, KIND, NAME, TEAM, STATE, BUNDLE.

            Examples:
              owlwatch login-items
              owlwatch login-items --enabled-only
              owlwatch login-items --kind app
              owlwatch login-items --team-id 2FNC3A47ZF
            """
    )

    @Flag(name: .long, help: "Only show enabled items.")
    var enabledOnly: Bool = false

    @Flag(name: .long, help: "Only show items in the current user's section (skip UID 0 and UID -2).")
    var userOnly: Bool = false

    @Option(
        name: .long,
        help: """
            Filter by kind: app | login-item | launch-agent | launch-daemon \
            | spotlight | quicklook | file-provider | legacy-agent.
            """
    )
    var kind: String?

    @Option(name: .long, help: "Filter by Team ID (10-character Apple developer team identifier).")
    var teamId: String?

    func run() throws {
        let items = OWPersistence.loginItems()
        let filtered = applyFilters(to: items)
        printTable(items: filtered)
    }

    private func applyFilters(to items: [LoginItem]) -> [LoginItem] {
        items.filter { item in
            if enabledOnly && !item.isEnabled { return false }
            if userOnly && item.userId != getuid() { return false }
            if let kind, parseKind(kind) != item.kind { return false }
            if let teamId, item.teamIdentifier != teamId { return false }
            return true
        }
    }

    private func parseKind(_ string: String) -> LoginItemKind? {
        switch string {
        case "app": return .app
        case "login-item": return .loginItem
        case "launch-agent": return .launchAgent
        case "launch-daemon": return .launchDaemon
        case "spotlight": return .spotlightImporter
        case "quicklook": return .quicklook
        case "file-provider": return .fileProvider
        case "legacy-agent": return .legacyAgent
        default: return nil
        }
    }

    private func printTable(items: [LoginItem]) {
        let sorted = items.sorted { lhs, rhs in
            if lhs.userId != rhs.userId { return lhs.userId < rhs.userId }
            return lhs.name < rhs.name
        }
        let rows = sorted.map(renderRow)
        let header = ["UID", "KIND", "NAME", "TEAM", "STATE", "BUNDLE"]
        let widths = columnWidths(header: header, rows: rows)
        print(formatRow(header, widths: widths))
        for row in rows {
            print(formatRow(row, widths: widths))
        }
    }

    private func renderRow(_ item: LoginItem) -> [String] {
        let uid = renderUid(item.userId)
        let kind = renderKind(item.kind)
        let name = item.name
        let team = item.teamIdentifier ?? "-"
        let state = item.disposition.symbolicForm
        let bundle = item.bundleIdentifier ?? "-"
        return [uid, kind, name, team, state, bundle]
    }

    private func renderUid(_ uid: uid_t) -> String {
        // UID -2 ("nobody") bridges to 4294967294 — render as -2 to match
        // sfltool's output and the way Apple documents this value.
        if uid == UInt32(bitPattern: -2) { return "-2" }
        return String(uid)
    }

    private func renderKind(_ kind: LoginItemKind) -> String {
        switch kind {
        case .app: return "app"
        case .loginItem: return "login-item"
        case .launchAgent: return "launch-agent"
        case .launchDaemon: return "launch-daemon"
        case .spotlightImporter: return "spotlight"
        case .quicklook: return "quicklook"
        case .fileProvider: return "file-provider"
        case .legacyAgent: return "legacy-agent"
        case .other(let rawName): return rawName
        }
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
