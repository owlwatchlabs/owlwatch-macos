import Foundation
import OWProcess

/// Drives the M16.2 Processes window. Snapshot of every visible
/// process (M1's `OWProcess.all(...)`) plus on-demand detail enrichment
/// for the currently-selected process.
///
/// **Two-phase loading.** `refresh()` calls `OWProcess.all(...)` with
/// `includeArguments: false, includeOpenFiles: false` — cheap, returns
/// hundreds of processes in milliseconds. When the user *selects* a
/// process, `loadDetail(for:)` re-fetches that one process with both
/// flags on, so the detail pane gets full argv and open-files info
/// without paying the cost across the whole table.
///
/// Same posture as `owlwatch ps`: unprivileged callers see only their
/// own processes' details (argv, files); root sees everything.
@MainActor
@Observable
final class ProcessesViewModel {
    var processes: [RunningProcess] = []

    /// Active sidebar tab — flat list or process tree.
    var selectedTab: ProcessesTab = .all

    /// Selected process's PID. Drives the right detail pane via
    /// ``detailProcess``.
    var selectedPID: pid_t?

    /// Full RunningProcess (with arguments + openFiles) for the
    /// currently-selected PID. Re-fetched whenever ``selectedPID``
    /// changes.
    var detailProcess: RunningProcess?

    /// Free-text filter against name + path + arguments.
    var searchText: String = ""

    var isLoading: Bool = false
    var detailLoading: Bool = false
    var lastRefresh: Date?

    /// Flat-list view of the snapshot, filtered by ``searchText``.
    var visibleProcesses: [RunningProcess] {
        let sorted = processes.sorted { $0.name.lowercased() < $1.name.lowercased() }
        guard !searchText.isEmpty else { return sorted }
        let needle = searchText.lowercased()
        return sorted.filter { process in
            process.name.lowercased().contains(needle)
                || (process.path?.lowercased().contains(needle) ?? false)
                || String(process.pid).contains(needle)
        }
    }

    /// Tree-view rendering: roots (processes whose parent isn't in the
    /// snapshot) at the top level, children grouped beneath their
    /// parent. Builds a `ProcessNode` tree.
    var processTree: [ProcessNode] {
        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        var childrenByParent: [pid_t: [RunningProcess]] = [:]
        for process in processes {
            childrenByParent[process.parentPid, default: []].append(process)
        }
        // A root is any process whose parentPid isn't in the snapshot
        // (or is the kernel pid 0).
        let roots = processes
            .filter { byPID[$0.parentPid] == nil || $0.parentPid == 0 }
            .sorted { $0.pid < $1.pid }
        return roots.map { buildNode($0, childrenByParent: childrenByParent) }
    }

    /// Refresh the snapshot. Off the main actor; results publish back
    /// here on completion.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        let snapshot: [RunningProcess] = await Task.detached {
            (try? OWProcess.all(includeArguments: false, includeOpenFiles: false)) ?? []
        }.value
        processes = snapshot
        lastRefresh = Date()

        // If the previously-selected PID is no longer present, drop
        // the selection.
        if let pid = selectedPID, !processes.contains(where: { $0.pid == pid }) {
            selectedPID = nil
            detailProcess = nil
        }
    }

    /// Load full process detail (argv + open files) for the selected
    /// PID. Called by the view when the selection changes.
    func loadDetail(for pid: pid_t) async {
        detailLoading = true
        defer { detailLoading = false }
        let process: RunningProcess? = await Task.detached {
            try? OWProcess.snapshot(pid: pid, includeArguments: true, includeOpenFiles: true)
        }.value
        // Only commit if the selection hasn't changed underneath us.
        guard selectedPID == pid else { return }
        detailProcess = process
    }

    /// Currently-selected process from the flat list — used by the
    /// detail pane to render headline info while the full detail
    /// (argv / files) is still loading.
    var selectedProcess: RunningProcess? {
        guard let pid = selectedPID else { return nil }
        return processes.first(where: { $0.pid == pid })
    }
}

/// Tabs shown in the Processes window sidebar.
enum ProcessesTab: String, CaseIterable, Identifiable, Hashable {
    case all
    case tree

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All Processes"
        case .tree: return "Process Tree"
        }
    }

    var symbolName: String {
        switch self {
        case .all: return "list.bullet"
        case .tree: return "rectangle.3.group"
        }
    }
}

/// Node in the process-tree view. SwiftUI's `OutlineGroup` consumes
/// this shape.
struct ProcessNode: Identifiable, Hashable {
    let process: RunningProcess
    let children: [ProcessNode]?  // nil = leaf; empty array = has-children-key-but-zero

    var id: pid_t { process.pid }
}

private func buildNode(
    _ process: RunningProcess,
    childrenByParent: [pid_t: [RunningProcess]]
) -> ProcessNode {
    let children = (childrenByParent[process.pid] ?? [])
        .sorted { $0.pid < $1.pid }
        .map { buildNode($0, childrenByParent: childrenByParent) }
    return ProcessNode(process: process, children: children.isEmpty ? nil : children)
}
