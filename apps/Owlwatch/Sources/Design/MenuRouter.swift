import Foundation

/// Section-switching helper for **non-`View` contexts** where the
/// consolidated window is already up — e.g. a future AppKit
/// `NSStatusItem` or a custom URL handler. Per DESIGN.md §9 the
/// router selects a section in the single window and brings it
/// forward; it never opens secondary windows.
///
/// **Not used by the SwiftUI menu bar.** The `MenuBarExtra` items
/// need `@Environment(\.openWindow)` to actually instantiate the
/// scene's window on first use (LSUIElement apps don't get a
/// window for free at launch), and that environment value is only
/// available inside a `View`. The menu-bar buttons inline that
/// logic. See `OwlwatchApp.OwlwatchMenuBarContent.open(_:)`.
enum MenuRouter {
    /// Switch the already-open window to `section` and front it.
    /// Silently does nothing for the section selection if the
    /// window scene doesn't exist yet (see ``AppModel/show(_:)``).
    @MainActor
    static func open(_ section: AppSection) {
        AppModel.shared.show(section)
    }
}
