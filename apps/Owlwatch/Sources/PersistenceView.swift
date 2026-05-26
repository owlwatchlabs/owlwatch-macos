import OWPersistence
import SwiftUI

/// The M17 Persistence section. SectionHeader (with SubnavPicker
/// over `PersistenceKind` + FilterField + refresh) on top; below, a
/// nested NavigationSplitView with center list + trailing detail.
/// The former per-window sub-sidebar (Launch Services / Login Items /
/// Kexts / …) is now the segmented sub-nav in the header per
/// DESIGN.md §10.3.
struct PersistenceView: View {
    @State private var viewModel = PersistenceViewModel()

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Persistence") {
                SubnavPicker(
                    selection: $viewModel.selectedKind,
                    options: PersistenceKind.allCases.map { ($0, $0.displayName) }
                )
                FilterField(text: $viewModel.searchText,
                            placeholder: "Filter by name or path")
                    .frame(maxWidth: 280)
                Spacer()
                refreshGroup
            }
            NavigationSplitView {
                PersistenceItemList(viewModel: viewModel)
                    .navigationSplitViewColumnWidth(min: 320, ideal: 420)
            } detail: {
                PersistenceItemDetail(item: viewModel.selectedItem)
                    .navigationSplitViewColumnWidth(min: 320, ideal: 380)
            }
            .tint(.owlAmber)
        }
        .task {
            // Kick off the FSEvents-backed mutation monitor for the
            // lifetime of the section. Cheap when idle (no events =
            // no work); auto-cancelled by SwiftUI when the task's
            // surrounding view goes away.
            viewModel.startLiveMonitor()
            if viewModel.lastRefresh == nil {
                await viewModel.refresh()
            }
        }
        .onDisappear {
            viewModel.stopLiveMonitor()
        }
    }

    @ViewBuilder
    private var refreshGroup: some View {
        if let last = viewModel.lastRefresh {
            Text("last refresh \(last.formatted(date: .omitted, time: .standard))")
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
