import SwiftUI

/// The single Owlwatch window's root.
///
/// `NavigationSplitView` with a sidebar of `AppSection` rows on the
/// left and the selected section's view on the right. Sub-categories
/// (All / Listeners / TCP …) live inside each section's header in
/// M17.3+, not as their own sidebar rows. See `docs/DESIGN.md` §9.
///
/// The detail switch reuses the existing top-level "window" views
/// (`DashboardWindow`, `PersistenceWindow`, etc.) as drop-in detail
/// content. These views still carry their own toolbars and
/// navigationTitles from the M16 era — that styling is reconciled
/// in M17.4 when each section is migrated to the design-system
/// component library.
struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(AppSection.allCases, selection: $model.section) { section in
            // SidebarRow per §10.1 lands in M17.3. For M17.2 a
            // plain Label gets us the icon + title in the sidebar
            // without committing to component-library structure.
            Label(section.title, systemImage: section.icon)
                .tag(section)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        .navigationTitle("Owlwatch")
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch model.section {
        case .dashboard:   DashboardView()
        case .processes:   ProcessesView()
        case .network:     NetworkView()
        case .persistence: PersistenceView()
        case .devices:     DevicesView()
        case .logs:        LogsView()
        case .inspector:   InspectorView()
        }
    }
}
