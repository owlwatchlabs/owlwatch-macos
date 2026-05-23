import SwiftUI

/// Center column. List of items in the currently-selected kind,
/// filtered by ``PersistenceViewModel/searchText``. Selecting a row
/// drives the right detail pane.
struct PersistenceItemList: View {
    @Bindable var viewModel: PersistenceViewModel

    var body: some View {
        let items = viewModel.visibleItems
        if items.isEmpty {
            ContentUnavailableView(
                emptyStateTitle,
                systemImage: viewModel.selectedKind.symbolName,
                description: Text(emptyStateBody)
            )
        } else {
            List(items, selection: $viewModel.selectedItemID) { item in
                PersistenceItemRow(item: item)
                    .tag(item.id)
            }
            .listStyle(.inset)
            .navigationTitle(viewModel.selectedKind.displayName)
            .navigationSubtitle("\(items.count) item\(items.count == 1 ? "" : "s")")
        }
    }

    private var emptyStateTitle: String {
        if viewModel.searchText.isEmpty {
            return "No \(viewModel.selectedKind.displayName)"
        }
        return "No matches"
    }

    private var emptyStateBody: String {
        if viewModel.searchText.isEmpty {
            switch viewModel.selectedKind {
            case .launchServices:
                return "No LaunchAgents or LaunchDaemons are installed."
            case .loginItems:
                return "BTM has no recorded login items."
            case .systemExtensions:
                return "No System Extensions are registered."
            case .kernelExtensions:
                return "No kexts found in /Library/Extensions or /System/Library/Extensions."
            case .loginHooks:
                return "No LoginHook or LogoutHook keys are set. (This is the normal state.)"
            case .liveEvents:
                return "Watching for filesystem changes across every persistence directory. "
                     + "Mutations will appear here as they happen."
            }
        }
        return "Filter '\(viewModel.searchText)' matched nothing."
    }
}

/// One row in the center list. Two-line layout: title + subtitle,
/// with a trailing state badge when applicable.
struct PersistenceItemRow: View {
    let item: PersistenceItem

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.displaySubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let label = item.stateLabel {
                Text(label)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(stateBackground(label))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    /// Color the state badge: green for active states, secondary for
    /// inactive, red for "awaiting user approval" (a security-relevant
    /// state for System Extensions).
    private func stateBackground(_ label: String) -> Color {
        switch label {
        case "enabled", "active", "activated_enabled":
            return .green.opacity(0.18)
        case "awaiting_user_approval":
            return .red.opacity(0.22)
        default:
            return .secondary.opacity(0.18)
        }
    }
}
