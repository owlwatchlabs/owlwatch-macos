import Foundation
import OWPersistence

/// The five persistence kinds the M5 viewer surfaces, in display order.
///
/// Order is deliberate: the most operationally-relevant surfaces
/// (Launch Services, Login Items) come first because those are where
/// real macOS malware persists most often. System Extensions and
/// Kernel Extensions sit in the middle (privileged but rare).
/// Login/Logout Hooks comes last (deprecated; usually empty).
enum PersistenceKind: String, CaseIterable, Identifiable, Hashable {
    case launchServices
    case loginItems
    case systemExtensions
    case kernelExtensions
    case loginHooks

    var id: String { rawValue }

    /// Short label for the sidebar.
    var displayName: String {
        switch self {
        case .launchServices: return "Launch Services"
        case .loginItems: return "Login Items"
        case .systemExtensions: return "System Extensions"
        case .kernelExtensions: return "Kernel Extensions"
        case .loginHooks: return "Login / Logout Hooks"
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
        }
    }
}

/// A unified view-layer wrapper over the five `OWPersistence` value types
/// so the SwiftUI list can be heterogeneous.
enum PersistenceItem: Identifiable, Hashable {
    case launchService(LaunchService)
    case loginItem(LoginItem)
    case systemExtension(SystemExtension)
    case kernelExtension(KernelExtension)
    case loginHook(LoginLogoutHook)

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
        }
    }

    var kind: PersistenceKind {
        switch self {
        case .launchService: return .launchServices
        case .loginItem: return .loginItems
        case .systemExtension: return .systemExtensions
        case .kernelExtension: return .kernelExtensions
        case .loginHook: return .loginHooks
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
        }
    }
}
