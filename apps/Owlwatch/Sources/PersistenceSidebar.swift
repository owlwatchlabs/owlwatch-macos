import SwiftUI

/// Left column. One row per ``PersistenceKind`` with a per-kind icon
/// and a trailing item-count badge.
struct PersistenceSidebar: View {
    @Bindable var viewModel: PersistenceViewModel

    var body: some View {
        List(PersistenceKind.allCases, selection: $viewModel.selectedKind) { kind in
            NavigationLink(value: kind) {
                Label(kind.displayName, systemImage: kind.symbolName)
                    .badge(viewModel.count(for: kind))
            }
        }
        .navigationTitle("Persistence")
    }
}
