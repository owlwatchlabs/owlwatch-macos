import OWProcess
import SwiftUI

/// The M18 Processes section.
///
/// Two panes: the M18.4 faceted list on the left
/// (`ProcessListView`) and the M18.5 triage dossier on the right
/// (`TriageDossier`). The list owns its own row model
/// (`ProcessListModel`); the dossier consumes a `ProcessRowVM`
/// directly. Argv + open-files loading is the
/// `ProcessesViewModel`'s job — it's narrow now, sourcing only
/// detail enrichment for the currently-selected pid.
struct ProcessesView: View {
    @State private var viewModel = ProcessesViewModel()
    @StateObject private var listModel = ProcessListModel()

    var body: some View {
        NavigationSplitView {
            ProcessListView(model: listModel)
                .navigationSplitViewColumnWidth(min: 420, ideal: 520)
        } detail: {
            if let row = listModel.rows.first(where: { $0.pid == listModel.selection }) {
                TriageDossier(row: row, listModel: listModel, viewModel: viewModel)
                    .navigationSplitViewColumnWidth(min: 360, ideal: 420)
            } else {
                EmptyState(text: "Select a process to see its details.")
                    .navigationSplitViewColumnWidth(min: 360, ideal: 420)
            }
        }
        .tint(.owlAmber)
        .task {
            if listModel.rows.isEmpty {
                await listModel.refresh()
            }
        }
        .onChange(of: listModel.selection) { _, newPID in
            // Deferred per the M18.2 fix so the .onChange mutation
            // doesn't trip the SwiftUI publishing-during-view-updates
            // fault.
            Task { @MainActor in
                viewModel.selectedPID = newPID
                if let pid = newPID {
                    await viewModel.loadDetail(for: pid)
                } else {
                    viewModel.detailProcess = nil
                }
            }
        }
    }
}
