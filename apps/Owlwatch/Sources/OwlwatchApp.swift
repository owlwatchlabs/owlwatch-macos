import AppKit
import SwiftUI

@main
struct OwlwatchApp: App {
    /// Stable identifier for the M17 consolidated single window.
    /// Wired into the SwiftUI scene declaration and used by
    /// `AppModel.show(_:)` to find and front the window.
    static let mainWindowID = "main"

    /// One shared model for the entire app — section selection,
    /// capture state, cross-link focus target. SwiftUI scenes can't
    /// take constructor args, so the menu router reaches in via
    /// `AppModel.shared`.
    @StateObject private var model = AppModel.shared

    /// Live status model that drives the menu-bar indicator and
    /// dropdown header. Kept from M16.6; reconciled with
    /// `AppModel.captureState` in M17.5.
    @State private var status = MenuBarStatusModel()

    var body: some Scene {
        MenuBarExtra {
            OwlwatchMenuBarContent(status: status)
                .task { status.start() }
        } label: {
            MenuBarIcon(status: status)
        }
        .menuBarExtraStyle(.menu)

        Window("Owlwatch", id: Self.mainWindowID) {
            RootView()
                .environmentObject(model)
                .tint(.owlAmber)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1180, height: 720)
        .windowResizability(.contentMinSize)
    }
}

/// The menu-bar icon. Swaps between a neutral shield, an in-use shield
/// (red), and an attention shield (orange, for recent TCC denials).
/// Driven by `MenuBarStatusModel`. Will swap to `OwlMark` tinted by
/// `statusColor(_:)` in M17.5 — kept as the shield variant here so
/// the icon doesn't regress mid-milestone.
private struct MenuBarIcon: View {
    @Bindable var status: MenuBarStatusModel

    var body: some View {
        if status.devicesInUseCount > 0 {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(.red)
        } else if status.recentTCCDenialCount > 0 {
            Image(systemName: "shield.fill")
                .foregroundStyle(.orange)
        } else {
            Image(systemName: "shield")
        }
    }
}

/// Content of the menu-bar dropdown. Live status header from M16.6
/// plus a single "Open Owlwatch" item that fronts the consolidated
/// window. M17.5 expands this back into per-section selectors that
/// drive `AppModel.show(_:)` instead of opening windows.
private struct OwlwatchMenuBarContent: View {
    @Bindable var status: MenuBarStatusModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // The header surfaces the same signal the menu-bar icon shows.
        // Buttons in a `.menu`-styled MenuBarExtra render as menu items,
        // not full Views — so the header is implemented as Text nodes,
        // not a custom HStack. macOS clips arbitrary layout in a menu
        // and the result looks broken.
        Text("Owlwatch")
            .font(.headline)
        if status.devicesInUseCount > 0 {
            Text(devicesSummary)
        }
        if status.recentTCCDenialCount > 0 {
            Text("\(status.recentTCCDenialCount) TCC denial(s) in last 5 min")
        }
        if status.devicesInUseCount == 0 && status.recentTCCDenialCount == 0 {
            Text("All quiet")
        }
        Divider()
        Button("Open Owlwatch") {
            // LSUIElement apps don't activate on openWindow alone —
            // the new window appears behind whatever's frontmost.
            // Explicit activation is required.
            NSApp.activate()
            openWindow(id: OwlwatchApp.mainWindowID)
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])
        Divider()
        Button("Quit Owlwatch") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var devicesSummary: String {
        var parts: [String] = []
        if status.cameraInUseCount > 0 {
            parts.append("\(status.cameraInUseCount) camera\(status.cameraInUseCount == 1 ? "" : "s")")
        }
        if status.microphoneInUseCount > 0 {
            parts.append("\(status.microphoneInUseCount) mic\(status.microphoneInUseCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: " + ") + " in use"
    }
}
