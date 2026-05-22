import AppKit
import SwiftUI

@main
struct OwlwatchApp: App {
    /// Stable identifier for the persistence-viewer window. Used by the
    /// MenuBarExtra's "Open Persistence View…" command via
    /// `openWindow(id:)`.
    static let persistenceWindowID = "persistence"

    var body: some Scene {
        MenuBarExtra("Owlwatch", systemImage: "shield") {
            OwlwatchMenuBarContent()
        }
        .menuBarExtraStyle(.menu)

        Window("Persistence — Owlwatch", id: Self.persistenceWindowID) {
            PersistenceWindow()
        }
        .defaultSize(width: 1100, height: 640)
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
        Button("Open Persistence View…") {
            openWindow(id: OwlwatchApp.persistenceWindowID)
        }
        .keyboardShortcut("p", modifiers: [.command, .shift])
        Divider()
        Button("Quit Owlwatch") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
