import Foundation

/// Top-level sections the single window cycles between. One enum
/// case per sidebar row in the consolidated UI; sub-categories
/// (All / Listeners / TCP …) live as `SubnavPicker` selections
/// inside each section's header rather than as their own sidebar
/// rows. See `docs/DESIGN.md` §9.
enum AppSection: String, CaseIterable, Identifiable {
    case dashboard
    case processes
    case network
    case persistence
    case devices
    case logs
    case inspector

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard:   return "Dashboard"
        case .processes:   return "Processes"
        case .network:     return "Network"
        case .persistence: return "Persistence"
        case .devices:     return "Devices"
        case .logs:        return "Logs"
        case .inspector:   return "Inspector"
        }
    }

    /// SF Symbol for sidebar + menu-bar rows.
    var icon: String {
        switch self {
        case .dashboard:   return "square.grid.2x2"
        case .processes:   return "cpu"
        case .network:     return "globe"
        case .persistence: return "play.circle"
        case .devices:     return "camera"
        case .logs:        return "doc.text"
        case .inspector:   return "doc.text.magnifyingglass"
        }
    }
}

/// Capture state for the menu-bar status indicator and the in-app
/// `OwlMark`. Three tri-state values, ordered so that ``cameraOrMicLive``
/// takes precedence over ``capturing`` when both apply (the
/// camera/mic case is the more urgent signal). See `DESIGN.md` §2.
enum CaptureState {
    /// Nothing is actively capturing — idle / quiet.
    case idle
    /// At least one Owlwatch subsystem is actively capturing data
    /// (live persistence stream, log tail, …) but no camera or mic
    /// is live.
    case capturing
    /// A camera or microphone is currently in use by some process.
    /// Outranks ``capturing`` — red wins over green.
    case cameraOrMicLive
}

/// Cross-link target — set by a detail panel to ask the next
/// section to pre-filter / pre-select something. The receiving
/// section's view reads this on appear and clears it via
/// ``AppModel/focus``.
enum FocusTarget: Equatable {
    /// Filter the target section by the given process PID.
    case process(Int32)
    /// Highlight the given socket (network section).
    case socket(UInt64)
    /// Pre-load the binary at the given URL (inspector section).
    case binary(URL)
}
