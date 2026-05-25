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
    /// dropdown header. Camera/mic in-use is mirrored into
    /// `AppModel.captureState` so the in-app `OwlMark` and the
    /// menu-bar mark stay in sync.
    @State private var status = MenuBarStatusModel()

    var body: some Scene {
        MenuBarExtra {
            OwlwatchMenuBarContent(status: status)
                .task { status.start() }
                .onChange(of: status.devicesInUseCount) { _, newCount in
                    model.captureState = newCount > 0 ? .cameraOrMicLive : .idle
                }
        } label: {
            MenuBarMark()
                .environmentObject(model)
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

/// The menu-bar mark — the same OwlMark from `Design/OwlMark.swift`
/// tinted by capture state. Per DESIGN.md §2: red (camera/mic live)
/// outranks green (capturing) outranks dim gold (idle).
///
/// SwiftUI's MenuBarExtra renders the label closure as a NSImage
/// internally; the resulting bitmap is **not** marked as a template,
/// so the gold/green/red disc colors come through.
private struct MenuBarMark: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        OwlMark(iris: statusColor(model.captureState))
            .frame(width: 18, height: 18)
    }
}

/// Content of the menu-bar dropdown. Live status header from M16.6
/// plus per-section open items (⌘⇧[DPSNLBI]) that select a section
/// in the single consolidated window via `MenuRouter`.
private struct OwlwatchMenuBarContent: View {
    @Bindable var status: MenuBarStatusModel

    var body: some View {
        // The header surfaces the same signal the menu-bar mark
        // shows, plus the TCC-denial count. Buttons in a `.menu`-
        // styled MenuBarExtra render as menu items, not full Views,
        // so the header is implemented as Text nodes — macOS clips
        // arbitrary layout in a menu and the result looks broken.
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
        Button("Open dashboard")    { MenuRouter.open(.dashboard) }
            .keyboardShortcut("h", modifiers: [.command, .shift])
        Divider()
        Button("Open processes")    { MenuRouter.open(.processes) }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        Button("Open network")      { MenuRouter.open(.network) }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        Button("Open persistence")  { MenuRouter.open(.persistence) }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        Button("Open devices")      { MenuRouter.open(.devices) }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        Button("Open logs")         { MenuRouter.open(.logs) }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        Button("Open inspector")    { MenuRouter.open(.inspector) }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        Divider()
        Button("Quit Owlwatch") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var devicesSummary: String {
        var parts: [String] = []
        if status.cameraInUseCount > 0 {
            parts.append("\(raw(status.cameraInUseCount)) camera\(status.cameraInUseCount == 1 ? "" : "s")")
        }
        if status.microphoneInUseCount > 0 {
            parts.append("\(raw(status.microphoneInUseCount)) mic\(status.microphoneInUseCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: " + ") + " in use"
    }
}
