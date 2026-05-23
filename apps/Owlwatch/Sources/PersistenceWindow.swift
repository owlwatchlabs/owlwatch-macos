import OWPersistence
import SwiftUI

/// Top-level window for the persistence viewer. Three-column
/// `NavigationSplitView`:
///
///   sidebar (kinds + counts) | center list (items) | trailing detail
///
/// Refreshes on first appearance and on demand via the toolbar
/// button. Search bar filters the center list.
struct PersistenceWindow: View {
    @State private var viewModel = PersistenceViewModel()

    var body: some View {
        NavigationSplitView {
            PersistenceSidebar(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } content: {
            PersistenceItemList(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 320, ideal: 420)
        } detail: {
            PersistenceItemDetail(item: viewModel.selectedItem)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380)
        }
        .navigationTitle("Persistence — Owlwatch")
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let last = viewModel.lastRefresh {
                    Text("Last refresh: \(last.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    if viewModel.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(viewModel.isLoading)
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Filter by name or path")
        .frame(minWidth: 880, minHeight: 480)
        .task {
            // Kick off the FSEvents-backed mutation monitor for the
            // lifetime of the window. Cheap when idle (no events =
            // no work); auto-cancelled by SwiftUI when the task
            // surrounding view goes away.
            viewModel.startLiveMonitor()
            // First-appearance snapshot refresh. Subsequent reloads
            // go through the toolbar button — we don't auto-poll.
            if viewModel.lastRefresh == nil {
                await viewModel.refresh()
            }
        }
        .onDisappear {
            viewModel.stopLiveMonitor()
        }
    }
}
