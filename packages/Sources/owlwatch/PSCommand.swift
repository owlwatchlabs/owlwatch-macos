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
            to include each process's `argv`. Use --files to include the
            count of open file descriptors per process. argv and FD lists
            are unavailable for other-user / SIP-protected processes when
            running unprivileged.
            """
    )

    @Flag(name: .shortAndLong, help: "Include the executable path as a column (table mode only).")
    var paths: Bool = false

    @Flag(name: .shortAndLong, help: "Include each process's argv (argv[0] is the invocation name).")
    var args: Bool = false

    @Flag(name: .shortAndLong, help: "Render as a pstree-style hierarchy.")
    var tree: Bool = false

    @Flag(name: .shortAndLong, help: "Include the open-file-descriptor count per process.")
    var files: Bool = false

    @Option(name: .long, help: "Focus on a single PID. In tree mode, shows the subtree rooted at that PID.")
    var pid: Int32?

    func run() throws {
        let allProcesses = try OWProcess.all(includeArguments: args, includeOpenFiles: files)
        let focused = focus(allProcesses, pid: pid, tree: tree)
        let output = tree
            ? renderTree(
                focused,
                includeArgs: args,
                includeFileCount: files,
                // When `--pid` filtered the snapshot, the focused process's
                // real parent is *intentionally* not in the set. Don't wrap
                // it in a `[unavailable]` synthetic header — the user asked
                // for this subtree explicitly.
                suppressSyntheticParentHeaders: pid != nil
            )
            : renderTable(
                focused.sorted { $0.pid < $1.pid },
                includePath: paths,
                includeArgs: args,
                includeFileCount: files
            )
        FileHandle.standardOutput.write(Data((output + "\n").utf8))
    }
}

// MARK: - --pid focus

/// Filters the snapshot to the focused PID.
///
/// In table mode, returns only the matching process (or empty if the PID is
/// not visible). In tree mode, returns the matching process **plus** every
/// descendant — so `owlwatch ps --tree --pid 1234` shows the subtree rooted
/// at PID 1234. When `pid` is `nil`, the snapshot is returned unchanged.
///
/// `internal` (not `private`) so unit tests can drive it with synthetic
/// snapshots without spawning the binary.
func focus(_ processes: [RunningProcess], pid: Int32?, tree: Bool) -> [RunningProcess] {
    guard let pid else { return processes }
    if !tree {
        return processes.filter { $0.pid == pid }
    }
    let childrenByParent = Dictionary(grouping: processes, by: \.parentPid)
    var collected: [RunningProcess] = []
    var queue: [pid_t] = [pid]
    while let next = queue.popLast() {
        if let proc = processes.first(where: { $0.pid == next }) {
            collected.append(proc)
        }
        if let children = childrenByParent[next] {
            queue.append(contentsOf: children.map(\.pid))
        }
    }
    return collected
}

// MARK: - Table rendering

@inline(__always)
private func renderTable(
    _ processes: [RunningProcess],
    includePath: Bool,
    includeArgs: Bool,
    includeFileCount: Bool
) -> String {
    var header = ["PID", "PPID", "USER", "NAME"]
    if includePath { header.append("PATH") }
    if includeFileCount { header.append("FDS") }
    if includeArgs { header.append("ARGS") }

    var rows: [[String]] = [header]
    for proc in processes {
        var row = [String(proc.pid), String(proc.parentPid), String(proc.userId), proc.name]
        if includePath { row.append(proc.path ?? "") }
        if includeFileCount { row.append(formatFileCount(proc.openFiles)) }
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

private func formatFileCount(_ openFiles: [OpenFile]?) -> String {
    guard let openFiles else { return "" }
    return openFiles.isEmpty ? "0" : String(openFiles.count)
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
private func renderTree(
    _ processes: [RunningProcess],
    includeArgs: Bool,
    includeFileCount: Bool,
    suppressSyntheticParentHeaders: Bool = false
) -> String {
    let childrenByParent = sortedChildren(by: \.parentPid, of: processes)
    let orphansByParent = sortedOrphans(of: processes)

    var renderer = TreeRenderer(
        childrenByParent: childrenByParent,
        includeArgs: includeArgs,
        includeFileCount: includeFileCount,
        suppressSyntheticParentHeaders: suppressSyntheticParentHeaders
    )
    for parentPid in orphansByParent.keys.sorted() {
        renderer.appendGroup(parentPid: parentPid, group: orphansByParent[parentPid] ?? [])
    }
    return renderer.lines.joined(separator: "\n")
}

private func sortedChildren(
    by parentKey: KeyPath<RunningProcess, pid_t>,
    of processes: [RunningProcess]
) -> [pid_t: [RunningProcess]] {
    var map: [pid_t: [RunningProcess]] = [:]
    for proc in processes {
        map[proc[keyPath: parentKey], default: []].append(proc)
    }
    for ppid in map.keys {
        map[ppid]?.sort { $0.pid < $1.pid }
    }
    return map
}

/// Builds the `parentPid -> [child]` map *only* for processes whose parent is
/// not represented in the snapshot. Each such group renders under a synthetic
/// `[unavailable](<ppid>)` header so the tree stays readable even when many
/// real parents are hidden by `proc_pidinfo` permissions.
private func sortedOrphans(of processes: [RunningProcess]) -> [pid_t: [RunningProcess]] {
    let pidSet = Set(processes.map { $0.pid })
    var map: [pid_t: [RunningProcess]] = [:]
    for proc in processes where !pidSet.contains(proc.parentPid) {
        map[proc.parentPid, default: []].append(proc)
    }
    for ppid in map.keys {
        map[ppid]?.sort { $0.pid < $1.pid }
    }
    return map
}

private let treeDepthLimit = 64

/// Stateful tree walker. The struct bundles the invariants (children map,
/// `includeArgs`) and the walk state (`visited`, `lines`) so individual
/// node-rendering methods stay small and have few parameters.
private struct TreeRenderer {
    let childrenByParent: [pid_t: [RunningProcess]]
    let includeArgs: Bool
    let includeFileCount: Bool
    let suppressSyntheticParentHeaders: Bool
    var visited: Set<pid_t> = []
    var lines: [String] = []

    mutating func appendGroup(parentPid: pid_t, group: [RunningProcess]) {
        if parentPid == 0 || suppressSyntheticParentHeaders {
            // PID 0 is the kernel scheduler; processes whose parent is the
            // kernel itself (in practice only launchd, when visible) render
            // as plain roots.
            // suppressSyntheticParentHeaders kicks in for --pid focused mode:
            // the focused PID's "missing parent" is the user's filter, not
            // a permission gap, so we skip the [unavailable] wrapper.
            for (index, proc) in group.enumerated() {
                appendNode(proc, prefix: "", isLast: index == group.count - 1, isRoot: true, depth: 0)
            }
        } else {
            lines.append("[unavailable](\(parentPid))")
            for (index, child) in group.enumerated() {
                appendNode(child, prefix: "", isLast: index == group.count - 1, isRoot: false, depth: 1)
            }
        }
    }

    mutating func appendNode(
        _ proc: RunningProcess,
        prefix: String,
        isLast: Bool,
        isRoot: Bool,
        depth: Int
    ) {
        guard !visited.contains(proc.pid), depth <= treeDepthLimit else { return }
        visited.insert(proc.pid)
        lines.append(formatNodeLine(proc, prefix: prefix, isRoot: isRoot, isLast: isLast))

        let children = childrenByParent[proc.pid] ?? []
        let nextPrefix = isRoot ? "" : (prefix + (isLast ? "    " : "│   "))
        for (index, child) in children.enumerated() {
            appendNode(
                child,
                prefix: nextPrefix,
                isLast: index == children.count - 1,
                isRoot: false,
                depth: depth + 1
            )
        }
    }

    private func formatNodeLine(
        _ proc: RunningProcess,
        prefix: String,
        isRoot: Bool,
        isLast: Bool
    ) -> String {
        let connector = isRoot ? "" : (isLast ? "└── " : "├── ")
        var line = "\(prefix)\(connector)\(proc.name)(\(proc.pid))"
        if includeFileCount, let openFiles = proc.openFiles {
            line += " [\(openFiles.count) fds]"
        }
        if includeArgs, let arguments = proc.arguments, arguments.count > 1 {
            let tail = arguments.dropFirst().joined(separator: " ")
            if !tail.isEmpty {
                line += " \(tail)"
            }
        }
        return line
    }
}
