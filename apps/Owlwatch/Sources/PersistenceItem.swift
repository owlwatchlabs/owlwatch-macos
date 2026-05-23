import Foundation
import OWPersistence

/// The six persistence views the M5/M10 viewer surfaces.
///
/// Snapshot kinds (M5) come first in display order, grouped by
/// operational relevance: Launch Services and Login Items at the top
/// because that's where real macOS malware persists most often;
/// System Extensions and Kernel Extensions in the middle; deprecated
/// Login/Logout Hooks last. The Live Events stream (M10.3) sits at
/// the bottom — visually separate from the snapshot kinds because
/// it answers a different question ("what just changed?" vs "what's
/// installed?").
enum PersistenceKind: String, CaseIterable, Identifiable, Hashable {
    case launchServices
    case loginItems
    case systemExtensions
    case kernelExtensions
    case loginHooks
    case liveEvents

    var id: String { rawValue }

    /// Short label for the sidebar.
    var displayName: String {
        switch self {
        case .launchServices: return "Launch Services"
        case .loginItems: return "Login Items"
        case .systemExtensions: return "System Extensions"
        case .kernelExtensions: return "Kernel Extensions"
        case .loginHooks: return "Login / Logout Hooks"
        case .liveEvents: return "Live Events"
        }
    }

    /// SF Symbol name for the sidebar icon.
    var symbolName: String {
        switch self {
        case .launchServices: return "play.circle"
        case .loginItems: return "person.circle"
        case .systemExtensions: return "puzzlepiece.extension"
        case .kernelExtensions: return "cpu"
        case .loginHooks: return "arrow.right.circle"
        case .liveEvents: return "dot.radiowaves.left.and.right"
        }
    }

    /// `true` for the live event stream — used by the UI to show the
    /// "● Live" indicator and different empty-state copy.
    var isLive: Bool {
        self == .liveEvents
    }
}

/// A unified view-layer wrapper over the `OWPersistence` value types
/// so the SwiftUI list can be heterogeneous across snapshot kinds
/// (M5) and live mutation events (M10.3).
enum PersistenceItem: Identifiable, Hashable {
    case launchService(LaunchService)
    case loginItem(LoginItem)
    case systemExtension(SystemExtension)
    case kernelExtension(KernelExtension)
    case loginHook(LoginLogoutHook)
    case liveMutation(EnrichedMutation)

    var id: String {
        switch self {
        case .launchService(let service):
            return "ls:\(service.scope.rawValue):\(service.plistPath)"
        case .loginItem(let item):
            return "li:\(item.uuid)"
        case .systemExtension(let ext):
            return "sx:\(ext.uniqueID ?? ext.bundleIdentifier)"
        case .kernelExtension(let ext):
            return "kx:\(ext.bundlePath)"
        case .loginHook(let hook):
            return "lh:\(hook.scope.rawValue):\(hook.kind.rawValue)"
        case .liveMutation(let event):
            // FSEvents IDs are unique per boot. Combine with the path
            // so distinct events on the same eventID (theoretically
            // possible) don't collide in SwiftUI selection.
            return "lm:\(event.mutation.eventID):\(event.mutation.path)"
        }
    }

    var kind: PersistenceKind {
        switch self {
        case .launchService: return .launchServices
        case .loginItem: return .loginItems
        case .systemExtension: return .systemExtensions
        case .kernelExtension: return .kernelExtensions
        case .loginHook: return .loginHooks
        case .liveMutation: return .liveEvents
        }
    }

    /// Primary label shown in the center list.
    var displayTitle: String {
        switch self {
        case .launchService(let service):
            return service.label ?? "(no Label)"
        case .loginItem(let item):
            return item.name
        case .systemExtension(let ext):
            return ext.bundleIdentifier
        case .kernelExtension(let ext):
            return ext.bundleIdentifier ?? ((ext.bundlePath as NSString).lastPathComponent)
        case .loginHook(let hook):
            return "\(hook.kind.rawValue.capitalized) hook (\(hook.scope.rawValue))"
        case .liveMutation(let event):
            // Prefer the parsed payload's label when the mutation
            // enriched cleanly; fall back to the path's basename.
            if let label = event.launchService?.label {
                return label
            }
            if let hook = event.hooks?.first {
                return "\(hook.kind.rawValue.capitalized) hook"
            }
            return (event.mutation.path as NSString).lastPathComponent
        }
    }

    /// Secondary label shown beneath the title.
    var displaySubtitle: String {
        switch self {
        case .launchService(let service):
            return service.executablePath ?? "(no Program)"
        case .loginItem(let item):
            return item.bundleIdentifier ?? item.identifier ?? item.uuid
        case .systemExtension(let ext):
            return ext.bundlePath
        case .kernelExtension(let ext):
            return ext.bundlePath
        case .loginHook(let hook):
            return hook.scriptPath
        case .liveMutation(let event):
            if let program = event.launchService?.executablePath {
                return program
            }
            return event.mutation.path
        }
    }

    /// Active/inactive label for the trailing tag in the list row.
    /// `nil` when the kind doesn't have a meaningful enabled state.
    var stateLabel: String? {
        switch self {
        case .launchService(let service):
            return service.isDisabled ? "disabled" : "enabled"
        case .loginItem(let item):
            return item.isEnabled ? "enabled" : "disabled"
        case .systemExtension(let ext):
            return ext.state.rawValue
        case .kernelExtension:
            return nil  // static inspection has no enabled/disabled signal
        case .loginHook:
            return "active"
        case .liveMutation(let event):
            // For mutations the badge is the kind itself — ADDED,
            // REMOVED, modified, etc. Detection rules and the UI
            // both want it at a glance.
            return renderMutationKind(event.mutation.kind)
        }
    }
}

/// Map ``MutationKind`` to the badge text the live-events row shows.
/// Uppercase for the high-priority kinds (added / removed / renamed)
/// to make them visually pop in the list; lowercase for the noisier
/// kinds (modified / metadata changes) that fire often but rarely
/// matter on their own.
private func renderMutationKind(_ kind: MutationKind) -> String {
    switch kind {
    case .added: return "ADDED"
    case .removed: return "REMOVED"
    case .renamed: return "RENAMED"
    case .modified: return "modified"
    case .xattrChanged: return "xattr"
    case .metadataChanged: return "metadata"
    }
}
