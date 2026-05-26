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
                    // Defer the AppModel mutation to the next runloop —
                    // .onChange fires during the view-update pass, and
                    // synchronously writing one ObservableObject inside
                    // another's onChange trips SwiftUI's "Publishing
                    // changes from within view updates" fault.
                    Task { @MainActor in
                        model.captureState = newCount > 0 ? .cameraOrMicLive : .idle
                    }
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

/// The menu-bar mark — same shape as `OwlMark`, but rendered via
/// AppKit and embedded as `Image(nsImage:)` so it shows up
/// reliably in the menu bar.
///
/// **Why not a SwiftUI Circle composition?** SwiftUI's MenuBarExtra
/// label closure passes through a coercion path that does not
/// faithfully render arbitrary shape views — the disc came out
/// invisible in M17.5's first attempt. The spec (`docs/DESIGN.md`
/// §2) already prescribes the AppKit path: draw the mark with
/// `NSBezierPath` into an `NSImage`, set `isTemplate = false` so
/// macOS doesn't auto-tint the gold/green/red disc to monochrome.
private struct MenuBarMark: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Image(nsImage: owlStatusImage(for: model.captureState))
            .renderingMode(.original)
    }
}

/// Render the Owlwatch mark as an `NSImage` sized for the menu bar.
/// Disc tinted per ``CaptureState``; pupil is a solid `owlBg`
/// circle at 38% of the disc diameter (the "real eye" per §4).
/// `isTemplate = false` is load-bearing — without it macOS forces
/// the bitmap to monochrome and the color signal is lost.
private func owlStatusImage(for state: CaptureState, size: CGFloat = 18) -> NSImage {
    let tint: NSColor
    switch state {
    case .idle:            tint = NSColor(owlHex: 0xE8C95A)  // owlAmber
    case .capturing:       tint = NSColor(owlHex: 0x3FBF95)  // owlGreen
    case .cameraOrMicLive: tint = NSColor(owlHex: 0xF0726F)  // owlRed
    }
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        tint.setFill()
        NSBezierPath(ovalIn: rect).fill()

        let pupilDiameter = rect.width * 0.38
        let pupilRect = NSRect(
            x: rect.midX - pupilDiameter / 2,
            y: rect.midY - pupilDiameter / 2,
            width: pupilDiameter,
            height: pupilDiameter
        )
        NSColor(owlHex: 0x0B0E11).setFill()
        NSBezierPath(ovalIn: pupilRect).fill()
        return true
    }
    image.isTemplate = false
    return image
}

private extension NSColor {
    convenience init(owlHex: UInt) {
        self.init(
            srgbRed: CGFloat((owlHex >> 16) & 0xff) / 255,
            green:   CGFloat((owlHex >> 8)  & 0xff) / 255,
            blue:    CGFloat( owlHex        & 0xff) / 255,
            alpha: 1
        )
    }
}

/// Content of the menu-bar dropdown. Live status header from M16.6
/// plus per-section open items (⌘⇧[HSNPDLI]) that select a section
/// in the single consolidated window and bring it forward.
private struct OwlwatchMenuBarContent: View {
    @Bindable var status: MenuBarStatusModel
    @Environment(\.openWindow) private var openWindow

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
        Button("Open overview")     { open(.overview) }
            .keyboardShortcut("h", modifiers: [.command, .shift])
        Divider()
        Button("Open processes")    { open(.processes) }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        Button("Open network")      { open(.network) }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        Button("Open persistence")  { open(.persistence) }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        Button("Open devices")      { open(.devices) }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        Button("Open logs")         { open(.logs) }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        Button("Open inspector")    { open(.inspector) }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        Divider()
        Button("Quit Owlwatch") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    /// Set the active section, ensure the window exists, then bring
    /// it forward. Calling `openWindow(id:)` is what makes this work
    /// in an LSUIElement app — `AppModel.shared.show(_:)` alone uses
    /// `NSApp.windows.first { id == "main" }`, which returns nil
    /// until SwiftUI has actually instantiated the scene's window.
    private func open(_ section: AppSection) {
        AppModel.shared.section = section
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: OwlwatchApp.mainWindowID)
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
