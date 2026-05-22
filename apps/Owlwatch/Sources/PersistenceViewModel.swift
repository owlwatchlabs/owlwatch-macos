import Foundation
import OWPersistence

/// Holds the snapshot of every persistence kind plus the UI state
/// (selection, filtering, loading) for the M5.5 persistence window.
///
/// Snapshot work runs off the main actor — `OWPersistence.loginItems()`
/// shells to `sfltool dumpbtm` which has been observed taking 5–60s,
/// and we don't want that to block the UI. Property mutations come
/// back to the main actor on completion.
@MainActor
@Observable
final class PersistenceViewModel {
    var launchServices: [LaunchService] = []
    var loginItems: [LoginItem] = []
    var systemExtensions: [SystemExtension] = []
    var kernelExtensions: [KernelExtension] = []
    var loginHooks: [LoginLogoutHook] = []

    var isLoading: Bool = false
    var lastRefresh: Date?

    /// Currently-selected sidebar kind. The center list shows items
    /// of this kind. Defaults to ``PersistenceKind/launchServices``.
    var selectedKind: PersistenceKind = .launchServices

    /// Currently-selected item id. Drives the right detail pane.
    var selectedItemID: String?

    /// Free-text filter applied to the center list. Matches against
    /// each item's `displayTitle` and `displaySubtitle`.
    var searchText: String = ""

    /// Item count for a given kind — drives the sidebar badges.
    func count(for kind: PersistenceKind) -> Int {
        items(for: kind).count
    }

    /// All items of the given kind, unfiltered.
    func items(for kind: PersistenceKind) -> [PersistenceItem] {
        switch kind {
        case .launchServices:
            return launchServices.map { .launchService($0) }
        case .loginItems:
            return loginItems.map { .loginItem($0) }
        case .systemExtensions:
            return systemExtensions.map { .systemExtension($0) }
        case .kernelExtensions:
            return kernelExtensions.map { .kernelExtension($0) }
        case .loginHooks:
            return loginHooks.map { .loginHook($0) }
        }
    }

    /// Items of ``selectedKind`` filtered by ``searchText``. Empty
    /// search returns everything.
    var visibleItems: [PersistenceItem] {
        let all = items(for: selectedKind)
        guard !searchText.isEmpty else { return all }
        let needle = searchText.lowercased()
        return all.filter { item in
            item.displayTitle.lowercased().contains(needle)
                || item.displaySubtitle.lowercased().contains(needle)
        }
    }

    /// The currently-selected item (looked up from ``selectedItemID``),
    /// scoped to the active kind. `nil` when nothing is selected.
    var selectedItem: PersistenceItem? {
        guard let id = selectedItemID else { return nil }
        return items(for: selectedKind).first(where: { $0.id == id })
    }

    /// Refresh every kind. Snapshot calls run off-main; the resulting
    /// arrays publish back here on the main actor.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        async let services = Task.detached { OWPersistence.launchServices() }.value
        async let btmItems = Task.detached { OWPersistence.loginItems() }.value
        async let sysExt = Task.detached { OWPersistence.systemExtensions() }.value
        async let kernExt = Task.detached { OWPersistence.kernelExtensions() }.value
        async let hookList = Task.detached { OWPersistence.loginLogoutHooks() }.value

        launchServices = await services
        loginItems = await btmItems
        systemExtensions = await sysExt
        kernelExtensions = await kernExt
        loginHooks = await hookList
        lastRefresh = Date()

        // Drop a stale selection if the underlying items changed.
        if let id = selectedItemID,
           !items(for: selectedKind).contains(where: { $0.id == id }) {
            selectedItemID = nil
        }
    }
}
