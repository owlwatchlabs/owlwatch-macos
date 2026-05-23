import AppKit
import SwiftUI

@main
struct OwlwatchApp: App {
    /// Live status model that drives the M16.6 menu-bar indicator and
    /// dropdown header. Started in the MenuBarExtra's content closure
    /// the first time the menu is built.
    @State private var status = MenuBarStatusModel()

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

    /// Stable identifier for the M16.4 logs-viewer window.
    static let logsWindowID = "logs"

    /// Stable identifier for the M16.5 binary-inspector window.
    static let binaryInspectorWindowID = "binary-inspector"

    var body: some Scene {
        MenuBarExtra {
            OwlwatchMenuBarContent(status: status)
                .task { status.start() }
        } label: {
            MenuBarIcon(status: status)
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

        Window("Logs — Owlwatch", id: Self.logsWindowID) {
            LogsWindow()
        }
        .defaultSize(width: 1180, height: 680)
        .windowResizability(.contentMinSize)

        Window("Binary Inspector — Owlwatch", id: Self.binaryInspectorWindowID) {
            BinaryInspectorWindow()
        }
        .defaultSize(width: 1100, height: 680)
        .windowResizability(.contentMinSize)
    }
}

/// The menu-bar icon. Swaps between a neutral shield, an in-use shield
/// (red), and an attention shield (orange, for recent TCC denials).
/// Driven by `MenuBarStatusModel`.
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

/// Content of the menu-bar dropdown. Carries the live status header
/// (devices in use, recent TCC denials) plus jump links to every
/// per-source window.
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
        Button("Open Logs View…") {
            NSApp.activate()
            openWindow(id: OwlwatchApp.logsWindowID)
        }
        .keyboardShortcut("l", modifiers: [.command, .shift])
        Button("Open Binary Inspector…") {
            NSApp.activate()
            openWindow(id: OwlwatchApp.binaryInspectorWindowID)
        }
        .keyboardShortcut("b", modifiers: [.command, .shift])
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
