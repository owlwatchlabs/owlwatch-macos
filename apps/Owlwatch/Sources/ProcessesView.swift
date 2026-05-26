import OWProcess
import SwiftUI

/// The M18.4 Processes section.
///
/// Two panes: the new faceted list on the left (see
/// `ProcessListView`), the existing M17.6 detail pane on the right.
/// The detail pane is reused as-is until M18.5 lands the rules-first
/// dossier; this PR is scoped to the left pane + the data joins
/// powering it.
struct ProcessesView: View {
    /// Detail-pane data layer. Owns selection + on-demand detail
    /// loading (argv + open files). M18.5 may absorb its
    /// responsibilities into `ProcessListModel`, but for M18.4 the
    /// two coexist with a small bridge in `.onChange`.
    @State private var viewModel = ProcessesViewModel()

    /// New M18.4 row model — owns the facets, query, and joined
    /// `[ProcessRowVM]`.
    @StateObject private var listModel = ProcessListModel()

    var body: some View {
        NavigationSplitView {
            ProcessListView(model: listModel)
                .navigationSplitViewColumnWidth(min: 420, ideal: 520)
        } detail: {
            ProcessesDetailPane(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380)
        }
        .tint(.owlAmber)
        .task {
            if listModel.rows.isEmpty {
                await listModel.refresh()
            }
        }
        .onChange(of: listModel.selection) { _, newPID in
            // Bridge to the detail pane's data layer. Deferred per
            // M18.2 fix so the .onChange mutation doesn't trip the
            // SwiftUI "publishing during view updates" fault.
            Task { @MainActor in
                viewModel.selectedPID = newPID
                if let pid = newPID {
                    await viewModel.loadDetail(for: pid)
                } else {
                    viewModel.detailProcess = nil
                }
            }
        }
        .onChange(of: listModel.rows) { _, rows in
            // Mirror identity stubs into ProcessesViewModel so the
            // existing detail pane's `selectedProcess` lookup
            // resolves by pid. M18.5 will drop this bridge by
            // having the detail pane consume `ProcessRowVM`
            // directly.
            Task { @MainActor in
                viewModel.processes = rows.map { row in
                    RunningProcess(
                        pid: row.pid,
                        parentPid: row.parentPid,
                        name: row.name,
                        path: row.path,
                        userId: row.userId,
                        arguments: nil,
                        openFiles: nil
                    )
                }
            }
        }
    }
}

// MARK: - Detail pane (M17.6; reused as-is until M18.5)

private struct ProcessesDetailPane: View {
    @Bindable var viewModel: ProcessesViewModel
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let process = viewModel.selectedProcess {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(process.name).font(.title2).bold()
                    Divider()
                    DetailField("PID", raw(process.pid))
                    DetailField("Parent PID", raw(process.parentPid))
                    DetailField("User ID", raw(process.userId))
                    DetailField("Path", process.path ?? "—")

                    Divider()
                    Text("Linked")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    crossLinks(for: process)

                    Divider()
                    Text("Arguments")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    argumentsView
                    Divider()
                    Text("Open Files (\(viewModel.detailProcess?.openFiles?.count ?? 0))")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    openFilesView
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            EmptyState(text: "Select a process to see its details.")
        }
    }

    @ViewBuilder
    private func crossLinks(for process: RunningProcess) -> some View {
        LinkedRow(
            icon: "globe",
            label: "Network · sockets owned by pid \(raw(process.pid))",
            tint: .owlBlue
        ) {
            model.focus = .process(pid: process.pid, name: process.name)
            model.section = .network
        }
        if let path = process.path {
            LinkedRow(
                icon: "doc.text.magnifyingglass",
                label: "Inspector · \((path as NSString).lastPathComponent)",
                tint: .owlAmber
            ) {
                model.focus = .binary(URL(fileURLWithPath: path))
                model.section = .inspector
            }
        }
        LinkedRow(
            icon: "lock.shield",
            label: "Logs · TCC events for \(process.name)",
            tint: .owlGreen
        ) {
            model.focus = .process(pid: process.pid, name: process.name)
            model.section = .logs
        }
    }

    @ViewBuilder
    private var argumentsView: some View {
        if viewModel.detailLoading && viewModel.detailProcess?.arguments == nil {
            ProgressView().controlSize(.small)
        } else if let args = viewModel.detailProcess?.arguments, !args.isEmpty {
            Text(args.joined(separator: " "))
                .font(.body.monospaced())
                .textSelection(.enabled)
        } else if viewModel.detailProcess?.arguments?.isEmpty == true {
            Text("(no arguments)")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Text("(loading…)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var openFilesView: some View {
        if viewModel.detailLoading && viewModel.detailProcess?.openFiles == nil {
            ProgressView().controlSize(.small)
        } else if let files = viewModel.detailProcess?.openFiles, !files.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                    Text(renderOpenFile(file))
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        } else if viewModel.detailProcess?.openFiles?.isEmpty == true {
            Text("(no open files visible to this user)")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Text("(loading…)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func renderOpenFile(_ file: OpenFile) -> String {
        switch file {
        case .file(let fd, let path):
            return "fd \(fd): \(path ?? "(unnamed vnode)")"
        case .socket(let fd, let family, let type):
            return "fd \(fd): socket (family=\(family), type=\(type))"
        case .pipe(let fd):
            return "fd \(fd): pipe"
        case .other(let fd, let rawType):
            return "fd \(fd): other (type=\(rawType))"
        }
    }
}

// MARK: - Shared primitives

private struct DetailField: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospaced())
                .textSelection(.enabled)
        }
    }
}
