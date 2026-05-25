import AppKit
import SwiftUI

/// One observable model the consolidated UI reads from. Holds the
/// active section, the menu-bar capture state, and a pending
/// cross-link target for section-to-section jumps. Single instance
/// shared between the SwiftUI scene and the AppKit
/// `NSStatusItem` menu router. See `docs/DESIGN.md` §9.
@MainActor
final class AppModel: ObservableObject {
    /// Singleton — the AppKit menu router and the SwiftUI scene
    /// both need to mutate the same instance. SwiftUI scenes can't
    /// take constructor args, so the indirection through `.shared`
    /// is necessary.
    static let shared = AppModel()

    /// Active sidebar section. Driving this value from anywhere
    /// (`AppModel.shared.section = .processes`) updates the
    /// detail pane.
    @Published var section: AppSection = .dashboard

    /// Coarse tri-state for the menu-bar mark color. Driven by the
    /// existing menu-bar status pipeline in `MenuBarStatusModel`
    /// (wired up in M17.5). Defaults to idle.
    @Published var captureState: CaptureState = .idle

    /// Pending cross-link target. A detail panel sets this and
    /// flips ``section`` to ask the next view to pre-filter /
    /// pre-select. The receiving view reads `focus` on appear and
    /// **must clear it** (`focus = nil`) so the same target
    /// doesn't reapply on later navigations.
    @Published var focus: FocusTarget?

    /// Bring the single window forward (if it exists) and switch to
    /// a section. Safe to call from anywhere that already has the
    /// window open — `NSApp.windows.first { id == … }` only finds an
    /// already-instantiated SwiftUI scene, so this **does not open
    /// the window the first time**.
    ///
    /// For LSUIElement apps the menu-bar `Open …` actions need to
    /// run `openWindow(id:)` from a `@Environment(\.openWindow)`
    /// view first to create the scene; once the window exists,
    /// `show(_:)` reliably re-fronts it on subsequent calls.
    func show(_ section: AppSection) {
        self.section = section
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows
            .first { $0.identifier?.rawValue == OwlwatchApp.mainWindowID }?
            .makeKeyAndOrderFront(nil)
    }
}

/// Maps a ``CaptureState`` to the disc color the menu-bar mark and
/// in-app `OwlMark` should render. Red precedes green when both
/// apply (camera/mic live is more urgent than generic capturing).
func statusColor(_ state: CaptureState) -> Color {
    switch state {
    case .idle:            return .owlAmber
    case .capturing:       return .owlGreen
    case .cameraOrMicLive: return .owlRed
    }
}
