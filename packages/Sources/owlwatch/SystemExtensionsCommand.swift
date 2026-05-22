import ArgumentParser
import Foundation
import OWPersistence

struct SystemExtensionsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "system-extensions",
        abstract: "List registered macOS System Extensions (Network, Endpoint Security, DriverKit).",
        discussion: """
            Reads the sysextd registry at /Library/SystemExtensions/db.plist \
            and prints one row per registered extension. The registry is \
            world-readable; no entitlements required.

            Output columns: STATE, CATEGORY, BUNDLE, TEAM, VERSION, PATH.

            Examples:
              owlwatch system-extensions
              owlwatch system-extensions --running-only
              owlwatch system-extensions --category endpoint-security
            """
    )

    @Flag(name: .long, help: "Only show extensions in the activated_enabled state.")
    var runningOnly: Bool = false

    @Option(
        name: .long,
        help: "Filter by category: driver | network | endpoint-security."
    )
    var category: String?

    func run() throws {
        let extensions = OWPersistence.systemExtensions()
        let filtered = applyFilters(to: extensions)
        printTable(extensions: filtered)
    }

    private func applyFilters(to extensions: [SystemExtension]) -> [SystemExtension] {
        extensions.filter { ext in
            if runningOnly && !ext.state.isRunning { return false }
            if let category, let want = parseCategory(category) {
                if !ext.categories.contains(want) { return false }
            }
            return true
        }
    }

    private func parseCategory(_ string: String) -> SystemExtensionCategory? {
        switch string {
        case "driver": return .driver
        case "network": return .networkExtension
        case "endpoint-security": return .endpointSecurity
        default: return nil
        }
    }

    private func printTable(extensions: [SystemExtension]) {
        if extensions.isEmpty {
            print("(no system extensions registered)")
            return
        }
        let sorted = extensions.sorted { $0.bundleIdentifier < $1.bundleIdentifier }
        let rows = sorted.map(renderRow)
        let header = ["STATE", "CATEGORY", "BUNDLE", "TEAM", "VERSION", "PATH"]
        let widths = columnWidths(header: header, rows: rows)
        print(formatRow(header, widths: widths))
        for row in rows {
            print(formatRow(row, widths: widths))
        }
    }

    private func renderRow(_ ext: SystemExtension) -> [String] {
        let state = ext.state.rawValue
        let category = ext.categories.first.map(renderCategory) ?? "-"
        let bundle = ext.bundleIdentifier
        let team = ext.teamIdentifier ?? "-"
        let version = ext.shortVersion ?? ext.bundleVersion ?? "-"
        return [state, category, bundle, team, version, ext.bundlePath]
    }

    private func renderCategory(_ category: SystemExtensionCategory) -> String {
        switch category {
        case .driver: return "driver"
        case .networkExtension: return "network"
        case .endpointSecurity: return "endpoint-security"
        case .other(let raw): return raw
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
