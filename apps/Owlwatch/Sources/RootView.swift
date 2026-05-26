import AppKit
import SwiftUI

/// The single Owlwatch window's root.
///
/// `NavigationSplitView` with a grouped sidebar (Overview, then a
/// `SYSTEM` cluster of live-state sections, then an unlabeled
/// Logs/Inspector cluster) on the left and the selected section's
/// view on the right. Sub-categories (All / Listeners / TCP …) live
/// inside each section's header — not as their own sidebar rows.
/// See `docs/DESIGN.md` §9 + M18 brief §2.
struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .onAppear {
            // The Info.plist sets LSUIElement = true so launch is a
            // menu-bar agent (no Dock icon, no ⌘Tab entry, no top
            // app menu). While a window is showing, promote to a
            // regular app so the user can ⌘Tab away and back. The
            // demotion in .onDisappear restores agent state when
            // the window closes.
            NSApp.setActivationPolicy(.regular)
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        // Per §2: Overview as a standalone row, then a "SYSTEM"-
        // labeled group for the live-state sections (Processes /
        // Network / Persistence / Devices), then an unlabeled group
        // for the tool-style sections (Logs / Inspector). The two
        // group dividers do the visual separation work.
        List(selection: $model.section) {
            row(.overview)

            Section("System") {
                row(.processes)
                row(.network)
                row(.persistence)
                row(.devices)
            }

            // Unlabeled cluster — the empty Section header renders
            // as a divider only.
            Section {
                row(.logs)
                row(.inspector)
            }
        }
        .listStyle(.sidebar)
        // Selection accent. Window-level .tint isn't reliably
        // propagating to List in macOS 14, so apply it here.
        .tint(.owlAmber)
        .environment(\.defaultMinListRowHeight, 30)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        .navigationTitle("Owlwatch")
    }

    @ViewBuilder
    private func row(_ section: AppSection) -> some View {
        Label(section.title, systemImage: section.icon)
            .font(.owlMono(13))
            .tag(section)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch model.section {
        case .overview:    OverviewView()
        case .processes:   ProcessesView()
        case .network:     NetworkView()
        case .persistence: PersistenceView()
        case .devices:     DevicesView()
        case .logs:        LogsView()
        case .inspector:   InspectorView()
        }
    }
}
