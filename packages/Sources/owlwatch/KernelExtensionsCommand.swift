import ArgumentParser
import Foundation
import OWPersistence

struct KernelExtensionsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "kernel-extensions",
        abstract: "List installed kernel extensions (kexts) under /System/Library/Extensions and /Library/Extensions.",
        discussion: """
            Walks both kext directories, parses each bundle's Contents/Info.plist, \
            and prints one row per installed kext. Static inspection only — does \
            not report whether each kext is currently loaded into the kernel.

            Output columns: SCOPE, BUNDLE, VERSION, EXEC, PATH.

            Examples:
              owlwatch kernel-extensions
              owlwatch kernel-extensions --third-party-only
              owlwatch kernel-extensions --bundle-id com.example.driver
            """
    )

    @Flag(name: .long, help: "Only show third-party kexts (skip /System/Library/Extensions).")
    var thirdPartyOnly: Bool = false

    @Option(name: .long, help: "Filter to one bundle identifier.")
    var bundleId: String?

    func run() throws {
        let extensions = OWPersistence.kernelExtensions()
        let filtered = applyFilters(to: extensions)
        printTable(extensions: filtered)
    }

    private func applyFilters(to extensions: [KernelExtension]) -> [KernelExtension] {
        extensions.filter { ext in
            if thirdPartyOnly && ext.scope != .system { return false }
            if let bundleId, ext.bundleIdentifier != bundleId { return false }
            return true
        }
    }

    private func printTable(extensions: [KernelExtension]) {
        if extensions.isEmpty {
            print("(no kernel extensions found)")
            return
        }
        let sorted = extensions.sorted { lhs, rhs in
            if lhs.scope != rhs.scope { return lhs.scope.rawValue < rhs.scope.rawValue }
            return (lhs.bundleIdentifier ?? "") < (rhs.bundleIdentifier ?? "")
        }
        let rows = sorted.map(renderRow)
        let header = ["SCOPE", "BUNDLE", "VERSION", "EXEC", "PATH"]
        let widths = columnWidths(header: header, rows: rows)
        print(formatRow(header, widths: widths))
        for row in rows {
            print(formatRow(row, widths: widths))
        }
    }

    private func renderRow(_ ext: KernelExtension) -> [String] {
        [
            ext.scope.rawValue,
            ext.bundleIdentifier ?? "-",
            ext.shortVersion ?? ext.bundleVersion ?? "-",
            ext.executableName ?? "-",
            ext.bundlePath
        ]
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
