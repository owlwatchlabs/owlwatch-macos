import Foundation

/// Thin wrapper around `AppModel.shared.show(_:)` for the menu-bar
/// dropdown's per-section items. Per DESIGN.md §9 the menu bar
/// **never opens secondary windows** — it selects a section in the
/// single consolidated window and brings it forward.
///
/// Modeled as an `enum` because every action is static dispatch on
/// the shared `AppModel`; there's no instance state to carry.
enum MenuRouter {
    /// Switch the consolidated window to `section` and front it.
    @MainActor
    static func open(_ section: AppSection) {
        AppModel.shared.show(section)
    }
}
