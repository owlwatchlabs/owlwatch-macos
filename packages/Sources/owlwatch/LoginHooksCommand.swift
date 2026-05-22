import ArgumentParser
import Foundation
import OWPersistence

struct LoginHooksCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "login-hooks",
        abstract: "List legacy LoginHook / LogoutHook persistence scripts.",
        discussion: """
            Reads /Library/Preferences/com.apple.loginwindow.plist and \
            ~/Library/Preferences/com.apple.loginwindow.plist for the \
            LoginHook and LogoutHook keys. Apple deprecated this mechanism \
            in favor of LaunchAgents long ago, but the runtime still honors \
            it and several historical macOS malware families used it \
            specifically because it stopped being audited.

            On a clean modern system this prints "(no login or logout hooks set)". \
            Any hook present is detection-worthy by default.

            Output columns: SCOPE, KIND, SCRIPT, PLIST.
            """
    )

    func run() throws {
        let hooks = OWPersistence.loginLogoutHooks()
        printTable(hooks: hooks)
    }

    private func printTable(hooks: [LoginLogoutHook]) {
        if hooks.isEmpty {
            print("(no login or logout hooks set)")
            return
        }
        let sorted = hooks.sorted { lhs, rhs in
            if lhs.scope != rhs.scope { return lhs.scope.rawValue < rhs.scope.rawValue }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        let rows = sorted.map(renderRow)
        let header = ["SCOPE", "KIND", "SCRIPT", "PLIST"]
        let widths = columnWidths(header: header, rows: rows)
        print(formatRow(header, widths: widths))
        for row in rows {
            print(formatRow(row, widths: widths))
        }
    }

    private func renderRow(_ hook: LoginLogoutHook) -> [String] {
        [hook.scope.rawValue, hook.kind.rawValue, hook.scriptPath, hook.plistPath]
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
