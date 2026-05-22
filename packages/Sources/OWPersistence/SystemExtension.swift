import Foundation

/// A modern macOS System Extension — Apple's framework for shipping
/// drivers, network filters/proxies, and Endpoint Security clients
/// from user-space (replacing the older kernel-extension mechanism).
///
/// Source of truth is `/Library/SystemExtensions/db.plist`, the registry
/// the `sysextd` daemon maintains. It's world-readable and contains
/// every extension that has been activated, awaiting approval, or
/// staged for removal.
///
/// For an EDR, system extensions are the *high-trust* persistence
/// surface — installing one requires user approval in System Settings,
/// a notarized Developer ID signature, and the host app must request
/// the appropriate entitlement. The detection question is rarely "is
/// there an extension?" but "is there an extension I didn't approve?"
/// — which lives in ``state`` and ``teamIdentifier``.
public struct SystemExtension: Sendable, Equatable, Hashable {
    /// Bundle identifier (`CFBundleIdentifier`) of the extension.
    public let bundleIdentifier: String

    /// 10-character Apple developer Team ID. `nil` for Apple-signed
    /// platform extensions (rare — Apple ships kexts, not sysexts, for
    /// most platform work).
    public let teamIdentifier: String?

    /// `CFBundleShortVersionString` — the human-readable version.
    public let shortVersion: String?

    /// `CFBundleVersion` — the build number / revision.
    public let bundleVersion: String?

    /// Absolute filesystem path to the `.systemextension` bundle, as
    /// recorded by `sysextd`. Typically inside the host app's
    /// `Contents/Library/SystemExtensions/` directory.
    public let bundlePath: String

    /// Per-extension UUID that `sysextd` assigns at installation time.
    /// `nil` if the registry entry doesn't include one.
    public let uniqueID: String?

    /// Apple-defined category strings declaring what the extension is
    /// — driver, network filter, ES client, etc. Most extensions are
    /// single-category; the registry models it as a list.
    public let categories: [SystemExtensionCategory]

    /// Activation state per `sysextd`. The malware-detection-relevant
    /// states are ``SystemExtensionState/awaitingUserApproval``
    /// (signals an install attempt) and
    /// ``SystemExtensionState/activatedEnabled`` (it's running).
    public let state: SystemExtensionState

    public init(
        bundleIdentifier: String,
        teamIdentifier: String?,
        shortVersion: String?,
        bundleVersion: String?,
        bundlePath: String,
        uniqueID: String?,
        categories: [SystemExtensionCategory],
        state: SystemExtensionState
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.teamIdentifier = teamIdentifier
        self.shortVersion = shortVersion
        self.bundleVersion = bundleVersion
        self.bundlePath = bundlePath
        self.uniqueID = uniqueID
        self.categories = categories
        self.state = state
    }
}

/// The kinds of System Extension Apple's framework supports. Raw values
/// are the strings stored in `db.plist` — useful for forward-compat
/// when Apple introduces new categories.
public enum SystemExtensionCategory: Sendable, Equatable, Hashable {
    /// `com.apple.system_extension.driver` — DriverKit drivers
    /// (replacing IOKit kexts).
    case driver

    /// `com.apple.system_extension.network_extension` — Network
    /// Extensions: filter providers, DNS proxies, content filters,
    /// VPN providers, packet tunnels. Owlwatch's M7 / M12 ship here.
    case networkExtension

    /// `com.apple.system_extension.endpoint_security` — Endpoint
    /// Security clients subscribing to ES events. Owlwatch's M8 ships
    /// here.
    case endpointSecurity

    /// Any other category Apple ships that we don't recognize.
    /// `rawValue` preserved for matching.
    case other(rawValue: String)

    /// String value as it appears in `db.plist`.
    public var rawValue: String {
        switch self {
        case .driver: return "com.apple.system_extension.driver"
        case .networkExtension: return "com.apple.system_extension.network_extension"
        case .endpointSecurity: return "com.apple.system_extension.endpoint_security"
        case .other(let raw): return raw
        }
    }

    static func from(rawValue: String) -> SystemExtensionCategory {
        switch rawValue {
        case "com.apple.system_extension.driver": return .driver
        case "com.apple.system_extension.network_extension": return .networkExtension
        case "com.apple.system_extension.endpoint_security": return .endpointSecurity
        default: return .other(rawValue: rawValue)
        }
    }
}

/// Activation state of a system extension. The values mirror the
/// strings `sysextd` stores in `db.plist`.
public enum SystemExtensionState: Sendable, Equatable, Hashable {
    /// `activated_enabled` — running and processing events.
    case activatedEnabled

    /// `activated_disabled` — installed but disabled by the user.
    case activatedDisabled

    /// `awaiting_user_approval` — install pending; needs the user to
    /// approve in System Settings → Privacy & Security. From a
    /// detection standpoint, this is the moment to alert.
    case awaitingUserApproval

    /// `staged` — pre-installed by the host app but not yet activated.
    case staged

    /// `terminated_waiting_to_uninstall` — being torn down.
    case terminatedWaitingToUninstall

    /// Unrecognized state string. `rawValue` preserved so detection
    /// rules can still match.
    case other(rawValue: String)

    /// `true` for states where the extension is actively running.
    public var isRunning: Bool {
        self == .activatedEnabled
    }

    /// String value as it appears in `db.plist`.
    public var rawValue: String {
        switch self {
        case .activatedEnabled: return "activated_enabled"
        case .activatedDisabled: return "activated_disabled"
        case .awaitingUserApproval: return "awaiting_user_approval"
        case .staged: return "staged"
        case .terminatedWaitingToUninstall: return "terminated_waiting_to_uninstall"
        case .other(let raw): return raw
        }
    }

    static func from(rawValue: String) -> SystemExtensionState {
        switch rawValue {
        case "activated_enabled": return .activatedEnabled
        case "activated_disabled": return .activatedDisabled
        case "awaiting_user_approval": return .awaitingUserApproval
        case "staged": return .staged
        case "terminated_waiting_to_uninstall": return .terminatedWaitingToUninstall
        default: return .other(rawValue: rawValue)
        }
    }
}
