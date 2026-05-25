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
    /// Hard cap on live mutation history retained in memory. Old
    /// events past this count are dropped from the tail. Persistence
    /// directories are usually quiet, so 500 events covers many hours
    /// of normal activity and several minutes of a noisy
    /// installer/update event burst.
    static let liveBufferCap = 500

    var launchServices: [LaunchService] = []
    var loginItems: [LoginItem] = []
    var systemExtensions: [SystemExtension] = []
    var kernelExtensions: [KernelExtension] = []
    var loginHooks: [LoginLogoutHook] = []

    /// Live FSEvents-backed mutation history. Newest-first.
    var liveMutations: [EnrichedMutation] = []

    /// Count of live events received since the user last viewed the
    /// Live tab. Drives the sidebar badge so the user notices new
    /// activity even while looking at a snapshot kind.
    var unseenLiveEventCount: Int = 0

    /// Long-running task driving the FSEvents subscription. `nil`
    /// when the monitor isn't running.
    @ObservationIgnored private var monitorTask: Task<Void, Never>?

    var isLoading: Bool = false
    var lastRefresh: Date?

    /// `true` once `OWPersistence.loginItems()` has been called
    /// successfully this session. Used to keep the sfltool prompt
    /// gated behind explicit user navigation to Login Items — the
    /// prompt fires once per process lifetime, not every refresh.
    @ObservationIgnored private var hasFetchedLoginItems: Bool = false

    /// Currently-selected sidebar kind. The center list shows items
    /// of this kind. Defaults to ``PersistenceKind/launchServices``.
    var selectedKind: PersistenceKind = .launchServices {
        didSet {
            // Visiting the Live tab clears the unread badge.
            if selectedKind == .liveEvents {
                unseenLiveEventCount = 0
            }
            // Selecting Login Items triggers a lazy first-fetch.
            // `sfltool dumpbtm` prompts for the user password, so we
            // never call it until the user explicitly looks at the
            // Login Items tab.
            if selectedKind == .loginItems && !hasFetchedLoginItems {
                Task { await fetchLoginItems() }
            }
        }
    }

    /// Currently-selected item id. Drives the right detail pane.
    var selectedItemID: String?

    /// Free-text filter applied to the center list. Matches against
    /// each item's `displayTitle` and `displaySubtitle`.
    var searchText: String = ""

    /// Item count for a given kind — drives the sidebar badges.
    func count(for kind: PersistenceKind) -> Int {
        if kind == .liveEvents {
            // Show the unread count when not viewing Live, otherwise
            // the total count of accumulated events.
            return selectedKind == .liveEvents ? liveMutations.count : unseenLiveEventCount
        }
        return items(for: kind).count
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
        case .liveEvents:
            return liveMutations.map { .liveMutation($0) }
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

    /// Start the FSEvents-backed live mutation monitor. Idempotent —
    /// calling it twice is a no-op.
    ///
    /// Mutations land in ``liveMutations`` newest-first, capped at
    /// ``liveBufferCap``. The unseen-event counter increments unless
    /// the user is already looking at the Live tab.
    func startLiveMonitor() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in OWPersistence.monitorEnriched() {
                    if Task.isCancelled { return }
                    await self.appendMutation(event)
                }
            } catch {
                // FSEvents stream errors are exceedingly rare; surface
                // to stderr (the macOS app's only log channel for now).
                // M10's window has no banner-error UI yet; revisit.
                NSLog("OWPersistence live monitor failed: %@", "\(error)")
            }
        }
    }

    /// Stop the live monitor. Called on window dismissal.
    func stopLiveMonitor() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func appendMutation(_ event: EnrichedMutation) {
        liveMutations.insert(event, at: 0)
        if liveMutations.count > Self.liveBufferCap {
            liveMutations.removeLast(liveMutations.count - Self.liveBufferCap)
        }
        if selectedKind != .liveEvents {
            unseenLiveEventCount += 1
        }
    }

    /// Refresh every kind **except login items**. Snapshot calls run
    /// off-main; the resulting arrays publish back here on the main
    /// actor.
    ///
    /// Login items are intentionally not part of the bulk refresh —
    /// `OWPersistence.loginItems()` shells to `sfltool dumpbtm`
    /// which prompts for the user password, so it only runs when
    /// the user explicitly selects the Login Items sub-tab (via the
    /// `selectedKind.didSet` lazy-fetch) or hits refresh while on
    /// that tab.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        async let services = Task.detached { OWPersistence.launchServices() }.value
        async let sysExt = Task.detached { OWPersistence.systemExtensions() }.value
        async let kernExt = Task.detached { OWPersistence.kernelExtensions() }.value
        async let hookList = Task.detached { OWPersistence.loginLogoutHooks() }.value

        launchServices = await services
        systemExtensions = await sysExt
        kernelExtensions = await kernExt
        loginHooks = await hookList
        lastRefresh = Date()

        // Refresh login items only if we've already paid the auth
        // prompt this session and the user is looking at that tab.
        if hasFetchedLoginItems && selectedKind == .loginItems {
            await fetchLoginItems()
        }

        // Drop a stale selection if the underlying items changed.
        if let id = selectedItemID,
           !items(for: selectedKind).contains(where: { $0.id == id }) {
            selectedItemID = nil
        }
    }

    /// Lazy login-items fetch. Called from `selectedKind.didSet` the
    /// first time the user selects Login Items, and from `refresh()`
    /// thereafter while on that tab. Idempotent — safe to call from
    /// either site.
    private func fetchLoginItems() async {
        let items = await Task.detached { OWPersistence.loginItems() }.value
        loginItems = items
        hasFetchedLoginItems = true
    }
}
