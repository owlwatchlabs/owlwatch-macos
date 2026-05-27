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
        // HSplitView (rather than a nested NavigationSplitView) is
        // intentional: SwiftUI's nested NavigationSplitView doesn't
        // honor the inner detail's `max: .infinity` column flex,
        // and the inner panes ended up locked to their ideal widths
        // with a dead band between them. HSplitView is a thin
        // NSSplitView wrapper that fills its parent and respects
        // per-pane `.frame` minimums.
        HSplitView {
            ProcessListView(model: listModel)
                .frame(minWidth: 420, idealWidth: 520, maxWidth: 720)
            Group {
                if let row = listModel.rows.first(where: { $0.pid == listModel.selection }) {
                    TriageDossier(row: row, listModel: listModel, viewModel: viewModel)
                } else {
                    EmptyState(text: "Select a process to see its details.")
                }
            }
            .frame(minWidth: 360, maxWidth: .infinity)
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
