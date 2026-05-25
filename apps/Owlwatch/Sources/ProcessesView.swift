import OWProcess
import SwiftUI

/// The M17 Processes section. SectionHeader (with SubnavPicker over
/// `ProcessesTab` + a FilterField + the refresh control) on top;
/// below, a nested NavigationSplitView with center list + trailing
/// detail. The former per-window sub-sidebar (All / Tree) is now
/// the segmented sub-nav in the header per DESIGN.md §10.3.
struct ProcessesView: View {
    @State private var viewModel = ProcessesViewModel()

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Processes") {
                SubnavPicker(
                    selection: $viewModel.selectedTab,
                    options: ProcessesTab.allCases.map { ($0, $0.displayName) }
                )
                FilterField(text: $viewModel.searchText,
                            placeholder: "Filter by name, path, or PID")
                    .frame(maxWidth: 320)
                Spacer()
                refreshGroup
            }
            NavigationSplitView {
                ProcessesCenterPane(viewModel: viewModel)
                    .navigationSplitViewColumnWidth(min: 360, ideal: 480)
            } detail: {
                ProcessesDetailPane(viewModel: viewModel)
                    .navigationSplitViewColumnWidth(min: 320, ideal: 380)
            }
        }
        .task {
            if viewModel.lastRefresh == nil {
                await viewModel.refresh()
            }
        }
        .onChange(of: viewModel.selectedPID) { _, newPID in
            if let pid = newPID {
                Task { await viewModel.loadDetail(for: pid) }
            } else {
                viewModel.detailProcess = nil
            }
        }
    }

    @ViewBuilder
    private var refreshGroup: some View {
        if let last = viewModel.lastRefresh {
            let when = last.formatted(date: .omitted, time: .standard)
            Text("last refresh \(when) · \(grouped(viewModel.processes.count)) processes")
                .font(.owlMono(11))
                .foregroundStyle(Color.owlTextDim)
        }
        Button {
            Task { await viewModel.refresh() }
        } label: {
            if viewModel.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(Color.owlTextMuted)
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
        .keyboardShortcut("r", modifiers: .command)
    }
}

// MARK: - Center pane

private struct ProcessesCenterPane: View {
    @Bindable var viewModel: ProcessesViewModel

    var body: some View {
        switch viewModel.selectedTab {
        case .all:
            ProcessesFlatList(viewModel: viewModel)
        case .tree:
            ProcessesTreeView(viewModel: viewModel)
        }
    }
}

private struct ProcessesFlatList: View {
    @Bindable var viewModel: ProcessesViewModel

    var body: some View {
        let items = viewModel.visibleProcesses
        if items.isEmpty {
            ContentUnavailableView(
                viewModel.searchText.isEmpty ? "No Processes" : "No Matches",
                systemImage: "cpu",
                description: Text(viewModel.searchText.isEmpty
                                  ? "OWProcess.all() returned an empty list."
                                  : "Filter '\(viewModel.searchText)' matched nothing.")
            )
        } else {
            List(items, id: \.pid, selection: $viewModel.selectedPID) { process in
                ProcessRow(process: process).tag(process.pid)
            }
            .listStyle(.inset)
        }
    }
}

private struct ProcessesTreeView: View {
    @Bindable var viewModel: ProcessesViewModel

    var body: some View {
        let nodes = viewModel.processTree
        if nodes.isEmpty {
            ContentUnavailableView(
                "No Processes",
                systemImage: "rectangle.3.group",
                description: Text("OWProcess.all() returned an empty list.")
            )
        } else {
            List(selection: $viewModel.selectedPID) {
                OutlineGroup(nodes, children: \.children) { node in
                    ProcessRow(process: node.process).tag(node.process.pid)
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct ProcessRow: View {
    let process: RunningProcess

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(process.pid)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(process.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let path = process.path {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Text("uid \(process.userId)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Detail pane

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

    /// Cross-link rows per DESIGN.md §6 — switch section and set
    /// `model.focus` so the target view can pre-filter to this
    /// process. Three jumps cover the common follow-the-thread
    /// flows from a process.
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
