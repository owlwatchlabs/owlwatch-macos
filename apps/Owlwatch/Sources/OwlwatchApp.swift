import AppKit
import SwiftUI

@main
struct OwlwatchApp: App {
    var body: some Scene {
        MenuBarExtra("Owlwatch", systemImage: "shield") {
            Text("Owlwatch — M0 placeholder")
                .font(.headline)
            Divider()
            Button("Quit Owlwatch") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .menuBarExtraStyle(.menu)
    }
}
