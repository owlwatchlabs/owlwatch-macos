import ArgumentParser
import Foundation
import OWProcess

struct PSCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ps",
        abstract: "List running processes visible to the current user.",
        discussion: """
            Each row is a snapshot at the moment of enumeration. Processes \
            the caller cannot inspect — other users' processes when running \
            unprivileged, system-protected processes — are silently omitted.

            Default output is a fixed-width table with PID, PPID, USER, NAME.
            Use --tree to render a pstree-style hierarchy instead. Use --args
            to include each process's `argv` (note: argv is unavailable for
            other-user / SIP-protected processes when running unprivileged).
            """
    )

    @Flag(name: .shortAndLong, help: "Include the executable path as a trailing column (table mode only).")
    var paths: Bool = false

    @Flag(name: .shortAndLong, help: "Include each process's argv (argv[0] is the invocation name; argv[1..] are arguments).")
    var args: Bool = false

    @Flag(name: .shortAndLong, help: "Render as a pstree-style hierarchy rooted at processes whose parent is not in the snapshot.")
    var tree: Bool = false

    func run() throws {
        let processes = try OWProcess.all(includeArguments: args)
        let output = tree
            ? renderTree(processes, includeArgs: args)
            : renderTable(processes.sorted { $0.pid < $1.pid }, includePath: paths, includeArgs: args)
        FileHandle.standardOutput.write(Data((output + "\n").utf8))
    }
}

// MARK: - Table rendering

@inline(__always)
private func renderTable(_ processes: [RunningProcess], includePath: Bool, includeArgs: Bool) -> String {
    var header = ["PID", "PPID", "USER", "NAME"]
    if includePath { header.append("PATH") }
    if includeArgs { header.append("ARGS") }

    var rows: [[String]] = [header]
    for proc in processes {
        var row = [String(proc.pid), String(proc.parentPid), String(proc.userId), proc.name]
        if includePath { row.append(proc.path ?? "") }
        if includeArgs { row.append(joinArgsForTable(proc.arguments)) }
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

private func joinArgsForTable(_ arguments: [String]?) -> String {
    guard let arguments, !arguments.isEmpty else { return "" }
    // Drop argv[0] (usually the executable path or invocation name —
    // already represented by NAME / PATH columns) for the table view.
    let tail = arguments.dropFirst()
    return tail.isEmpty ? "" : tail.joined(separator: " ")
}

// MARK: - Tree rendering

/// Renders processes as a pstree-style hierarchy.
///
/// Children are grouped by `parentPid` and sorted by PID for stable output.
/// Roots are processes whose `parentPid` is not represented in the snapshot.
///
/// On unprivileged macOS callers, `proc_pidinfo` refuses to return metadata
/// for many system processes (launchd at PID 1, root-owned daemons). The
/// renderer groups visible children of an invisible parent under a synthetic
/// placeholder line so the tree's shape stays meaningful instead of degenerating
/// into a flat list of "roots." Running with `sudo` collapses the placeholders
/// because more parents become visible.
///
/// The tree walk has a hard depth cap of 64 to guard against pathological
/// cycles (which should not occur with a consistent kernel snapshot, but
/// the cap is cheap insurance).
private func renderTree(_ processes: [RunningProcess], includeArgs: Bool) -> String {
    let pidSet = Set(processes.map { $0.pid })
    var childrenByParent: [pid_t: [RunningProcess]] = [:]
    for proc in processes {
        childrenByParent[proc.parentPid, default: []].append(proc)
    }
    for ppid in childrenByParent.keys {
        childrenByParent[ppid]?.sort { $0.pid < $1.pid }
    }

    // Group processes whose parent is not in the snapshot by that parent's PID.
    // Each group renders under a synthetic "[unavailable]" header so the user
    // can see "these processes all descend from PID N which I can't inspect"
    // rather than seeing N flat roots.
    var orphansByParent: [pid_t: [RunningProcess]] = [:]
    for proc in processes where !pidSet.contains(proc.parentPid) {
        orphansByParent[proc.parentPid, default: []].append(proc)
    }
    for ppid in orphansByParent.keys {
        orphansByParent[ppid]?.sort { $0.pid < $1.pid }
    }

    var lines: [String] = []
    var visited = Set<pid_t>()

    let parentPids = orphansByParent.keys.sorted()
    for parentPid in parentPids {
        let group = orphansByParent[parentPid] ?? []
        if parentPid == 0 {
            // PID 0 = scheduler / kernel; processes whose parent is the kernel
            // itself (in practice only launchd, when visible) render as plain roots.
            for (i, proc) in group.enumerated() {
                renderTreeNode(
                    proc,
                    childrenByParent: childrenByParent,
                    prefix: "",
                    isLast: i == group.count - 1,
                    isRoot: true,
                    depth: 0,
                    includeArgs: includeArgs,
                    visited: &visited,
                    into: &lines
                )
            }
        } else {
            lines.append("[unavailable](\(parentPid))")
            for (i, child) in group.enumerated() {
                renderTreeNode(
                    child,
                    childrenByParent: childrenByParent,
                    prefix: "",
                    isLast: i == group.count - 1,
                    isRoot: false,
                    depth: 1,
                    includeArgs: includeArgs,
                    visited: &visited,
                    into: &lines
                )
            }
        }
    }
    return lines.joined(separator: "\n")
}

private let treeDepthLimit = 64

private func renderTreeNode(
    _ proc: RunningProcess,
    childrenByParent: [pid_t: [RunningProcess]],
    prefix: String,
    isLast: Bool,
    isRoot: Bool,
    depth: Int,
    includeArgs: Bool,
    visited: inout Set<pid_t>,
    into lines: inout [String]
) {
    if visited.contains(proc.pid) || depth > treeDepthLimit {
        return
    }
    visited.insert(proc.pid)

    let connector = isRoot ? "" : (isLast ? "└── " : "├── ")
    var line = "\(prefix)\(connector)\(proc.name)(\(proc.pid))"
    if includeArgs, let arguments = proc.arguments, arguments.count > 1 {
        let tail = arguments.dropFirst().joined(separator: " ")
        if !tail.isEmpty {
            line += " \(tail)"
        }
    }
    lines.append(line)

    let children = childrenByParent[proc.pid] ?? []
    let nextPrefix = isRoot ? "" : (prefix + (isLast ? "    " : "│   "))
    for (i, child) in children.enumerated() {
        renderTreeNode(
            child,
            childrenByParent: childrenByParent,
            prefix: nextPrefix,
            isLast: i == children.count - 1,
            isRoot: false,
            depth: depth + 1,
            includeArgs: includeArgs,
            visited: &visited,
            into: &lines
        )
    }
}
