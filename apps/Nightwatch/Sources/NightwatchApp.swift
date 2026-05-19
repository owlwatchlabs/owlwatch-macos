import AppKit
import SwiftUI

@main
struct NightwatchApp: App {
    var body: some Scene {
        MenuBarExtra("Nightwatch", systemImage: "shield") {
            Text("Nightwatch — M0 placeholder")
                .font(.headline)
            Divider()
            Button("Quit Nightwatch") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .menuBarExtraStyle(.menu)
    }
}
