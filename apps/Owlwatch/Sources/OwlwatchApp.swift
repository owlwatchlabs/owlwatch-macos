import AppKit
import SwiftUI

@main
struct OwlwatchApp: App {
    /// Stable identifier for the M16.1 status dashboard — the new
    /// app "home" reachable via "Open Dashboard…" (⌘⇧H).
    static let dashboardWindowID = "dashboard"

    /// Stable identifier for the persistence-viewer window. Used by the
    /// MenuBarExtra's "Open Persistence View…" command via
    /// `openWindow(id:)`.
    static let persistenceWindowID = "persistence"

    /// Stable identifier for the M11.4 devices-viewer window.
    static let devicesWindowID = "devices"

    /// Stable identifier for the M16.2 processes-viewer window.
    static let processesWindowID = "processes"

    /// Stable identifier for the M16.3 network-viewer window.
    static let networkWindowID = "network"

    var body: some Scene {
        MenuBarExtra("Owlwatch", systemImage: "shield") {
            OwlwatchMenuBarContent()
        }
        .menuBarExtraStyle(.menu)

        Window("Dashboard — Owlwatch", id: Self.dashboardWindowID) {
            DashboardWindow()
        }
        .defaultSize(width: 820, height: 620)
        .windowResizability(.contentMinSize)

        Window("Persistence — Owlwatch", id: Self.persistenceWindowID) {
            PersistenceWindow()
        }
        .defaultSize(width: 1100, height: 640)
        .windowResizability(.contentMinSize)

        Window("Devices — Owlwatch", id: Self.devicesWindowID) {
            DevicesWindow()
        }
        .defaultSize(width: 980, height: 580)
        .windowResizability(.contentMinSize)

        Window("Processes — Owlwatch", id: Self.processesWindowID) {
            ProcessesWindow()
        }
        .defaultSize(width: 1040, height: 620)
        .windowResizability(.contentMinSize)

        Window("Network — Owlwatch", id: Self.networkWindowID) {
            NetworkWindow()
        }
        .defaultSize(width: 1080, height: 620)
        .windowResizability(.contentMinSize)
    }
}

/// Content of the menu-bar dropdown. Keeps the existing M0 placeholder
/// shape but adds the entry point for the M5.5 persistence viewer.
private struct OwlwatchMenuBarContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Owlwatch")
            .font(.headline)
        Divider()
        Button("Open Dashboard…") {
            NSApp.activate()
            openWindow(id: OwlwatchApp.dashboardWindowID)
        }
        .keyboardShortcut("h", modifiers: [.command, .shift])
        Divider()
        Button("Open Persistence View…") {
            // LSUIElement apps do not activate when a window is opened —
            // the new window appears behind the currently-frontmost app
            // unless we explicitly activate ourselves. NSApp.activate()
            // (the no-arg form available on macOS 14+) is what
            // SwiftUI's default Dock-icon apps do under the hood.
            NSApp.activate()
            openWindow(id: OwlwatchApp.persistenceWindowID)
        }
        .keyboardShortcut("p", modifiers: [.command, .shift])
        Button("Open Devices View…") {
            NSApp.activate()
            openWindow(id: OwlwatchApp.devicesWindowID)
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])
        Button("Open Processes View…") {
            NSApp.activate()
            openWindow(id: OwlwatchApp.processesWindowID)
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])
        Button("Open Network View…") {
            NSApp.activate()
            openWindow(id: OwlwatchApp.networkWindowID)
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])
        Divider()
        Button("Quit Owlwatch") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
