import ArgumentParser
import Foundation
import NWProcess

struct PSCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ps",
        abstract: "List running processes visible to the current user.",
        discussion: """
            Each row is a snapshot at the moment of enumeration. Processes \
            the caller cannot inspect — other users' processes when running \
            unprivileged, system-protected processes — are silently omitted.

            Columns:
              PID   process id
              PPID  parent process id
              USER  numeric user id
              NAME  process name from libproc's pbi_name (falls back to pbi_comm)
            """
    )

    @Flag(name: .shortAndLong, help: "Include the executable path as a trailing column.")
    var paths: Bool = false

    func run() throws {
        let processes = try NWProcess.all().sorted { $0.pid < $1.pid }
        let table = renderTable(processes, includePath: paths)
        FileHandle.standardOutput.write(Data((table + "\n").utf8))
    }
}

@inline(__always)
private func renderTable(_ processes: [RunningProcess], includePath: Bool) -> String {
    var rows: [[String]] = [["PID", "PPID", "USER", "NAME"]]
    if includePath {
        rows[0].append("PATH")
    }
    for proc in processes {
        var row = [String(proc.pid), String(proc.parentPid), String(proc.userId), proc.name]
        if includePath {
            row.append(proc.path ?? "")
        }
        rows.append(row)
    }

    let columnCount = rows[0].count
    let widths: [Int] = (0..<columnCount).map { col in
        rows.map { $0[col].count }.max() ?? 0
    }

    return rows.map { row in
        row.enumerated().map { idx, cell in
            idx == columnCount - 1
                ? cell
                : cell.padding(toLength: widths[idx], withPad: " ", startingAt: 0)
        }.joined(separator: "  ")
    }.joined(separator: "\n")
}
