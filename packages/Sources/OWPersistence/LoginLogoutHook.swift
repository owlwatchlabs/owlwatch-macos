import Foundation

/// A legacy login or logout hook.
///
/// Set via `defaults write com.apple.loginwindow LoginHook /path/to/script`
/// (or `LogoutHook`). The path lives in
/// `/Library/Preferences/com.apple.loginwindow.plist` for system-wide
/// hooks and `~/Library/Preferences/com.apple.loginwindow.plist` for
/// per-user. Apple deprecated this mechanism around 10.5 in favor of
/// LaunchAgents, but the runtime still honors the keys and several
/// historical macOS malware families used it specifically because it
/// was no longer audited.
///
/// Both plists are world-readable. Most modern systems have zero hooks;
/// any hook present is detection-worthy by default.
public struct LoginLogoutHook: Sendable, Equatable, Hashable {
    /// Whether the hook fires on login (``HookKind/login``) or logout
    /// (``HookKind/logout``).
    public let kind: HookKind

    /// Scope the hook is set in: system-wide (`/Library/Preferences`)
    /// or per-user (`~/Library/Preferences`).
    public let scope: HookScope

    /// Path to the script the hook runs.
    public let scriptPath: String

    /// Path to the plist where the hook key lives.
    public let plistPath: String

    public init(
        kind: HookKind,
        scope: HookScope,
        scriptPath: String,
        plistPath: String
    ) {
        self.kind = kind
        self.scope = scope
        self.scriptPath = scriptPath
        self.plistPath = plistPath
    }
}

/// Whether a hook fires on login or logout.
public enum HookKind: String, Sendable, Equatable, Hashable, CaseIterable {
    case login
    case logout

    /// The plist key name corresponding to this hook kind.
    public var plistKey: String {
        switch self {
        case .login: return "LoginHook"
        case .logout: return "LogoutHook"
        }
    }
}

/// Where a hook plist lives — system-wide or per-user.
public enum HookScope: String, Sendable, Equatable, Hashable, CaseIterable {
    /// `/Library/Preferences/com.apple.loginwindow.plist` —
    /// system-wide, set by admin.
    case system

    /// `~/Library/Preferences/com.apple.loginwindow.plist` — per-user.
    case user

    /// Filesystem path the scope's plist lives at. `~` is expanded to
    /// the current user's home for ``user``.
    public var plistPath: String {
        switch self {
        case .system:
            return "/Library/Preferences/com.apple.loginwindow.plist"
        case .user:
            return (NSHomeDirectory() as NSString)
                .appendingPathComponent("Library/Preferences/com.apple.loginwindow.plist")
        }
    }
}
