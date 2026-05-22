import Darwin
import Foundation

/// A single Background Task Management (BTM) record — what macOS calls
/// a "login item" in System Settings, plus everything else `launchctl
/// print-btm` / `sfltool dumpbtm` surfaces (apps with login behavior,
/// SMAppService-registered agents, Spotlight importers, QuickLook
/// extensions, legacy launch-services entries).
///
/// Source of truth is the BTM database under
/// `/var/db/com.apple.backgroundtaskmanagementagent/` which is not
/// readable by ordinary users; `sfltool dumpbtm` is Apple's
/// user-mode reader and is what `OWPersistence.loginItems()` shells
/// to. Parsing is best-effort: the output format is structured but
/// not contractually stable, so the parser preserves both the
/// classified enum (``kind``) and the raw text/value as the kernel
/// reports it (``kindRawValue``, ``LoginItemKind/other(rawName:)``).
///
/// For an EDR, the detection-relevant facts are: *which user owns
/// it* (``userId``), *what triggers it* (``kind``), *is it currently
/// active* (``isEnabled``), and *who signed the binary*
/// (``teamIdentifier`` — cross-reference with `OWCodeSigning`).
public struct LoginItem: Sendable, Equatable, Hashable {
    /// Per-item BTM UUID, stable across reboots until the item is
    /// re-registered.
    public let uuid: String

    /// Owning user. `0` for system, `4294967294` (UID -2, "nobody")
    /// for a placeholder section that's always present, or a real
    /// `uid_t` for per-user records.
    public let userId: uid_t

    /// Display name as `sfltool` reports it. For app records this
    /// is typically the bundle's `CFBundleDisplayName`.
    public let name: String

    /// `Developer Name` from BTM. `nil` when unset (`(null)` in the
    /// raw output).
    public let developerName: String?

    /// `Team Identifier` from BTM — the 10-character Apple developer
    /// Team ID. `nil` for Apple-signed (platform binary) entries.
    public let teamIdentifier: String?

    /// `Bundle Identifier` (`CFBundleIdentifier`). `nil` for entries
    /// without a bundle.
    public let bundleIdentifier: String?

    /// `Parent Identifier` — the BTM-internal identifier of the parent
    /// app, for plug-in / extension records (QuickLook extensions
    /// attached to their host app, etc.).
    public let parentIdentifier: String?

    /// BTM-internal identifier, format `<typecode>.<bundleId>`
    /// (e.g. `2.com.spotify.client` for an app entry, `4.com.foo`
    /// for a login item). The numeric prefix duplicates ``kindRawValue``.
    public let identifier: String?

    /// File URL or relative-to-parent URL fragment. Apps use absolute
    /// `file://` URLs; plug-ins use relative paths like
    /// `Contents/PlugIns/Foo.appex`.
    public let url: String?

    /// Classified record kind — see ``LoginItemKind``. Unknown raw
    /// values land in ``LoginItemKind/other(rawName:)`` with the
    /// raw string preserved.
    public let kind: LoginItemKind

    /// Raw BTM type bitfield. `0x2` for apps, `0x4` for login items,
    /// `0x800` for QuickLook, etc.
    public let kindRawValue: Int

    /// Disposition bitfield from BTM — enabled / allowed / notified.
    public let disposition: LoginItemDisposition

    /// Convenience: ``disposition`` contains ``LoginItemDisposition/enabled``.
    public var isEnabled: Bool { disposition.contains(.enabled) }

    public init(
        uuid: String,
        userId: uid_t,
        name: String,
        developerName: String?,
        teamIdentifier: String?,
        bundleIdentifier: String?,
        parentIdentifier: String?,
        identifier: String?,
        url: String?,
        kind: LoginItemKind,
        kindRawValue: Int,
        disposition: LoginItemDisposition
    ) {
        self.uuid = uuid
        self.userId = userId
        self.name = name
        self.developerName = developerName
        self.teamIdentifier = teamIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.parentIdentifier = parentIdentifier
        self.identifier = identifier
        self.url = url
        self.kind = kind
        self.kindRawValue = kindRawValue
        self.disposition = disposition
    }
}

/// Classified BTM record kind. Raw values are the bitfield BTM uses
/// internally; the enum collapses each known value to its name.
/// Unknown values land in ``other(rawName:)`` with the textual form
/// from `sfltool` preserved.
public enum LoginItemKind: Sendable, Equatable, Hashable {
    /// `0x2` — a standalone application (Spotify, Xcode, ...).
    case app

    /// `0x4` — a login-item helper bundle inside an app
    /// (`Contents/Library/LoginItems/*.app`). Registered via the
    /// legacy `SMLoginItemSetEnabled` API or modern `SMAppService`.
    case loginItem

    /// `0x8` — Launch Agent registered via `SMAppService.agent(plistName:)`.
    /// Distinct from a free-standing `~/Library/LaunchAgents` plist.
    case launchAgent

    /// `0x10` — Launch Daemon registered via `SMAppService.daemon(plistName:)`.
    case launchDaemon

    /// `0x40` — Spotlight metadata importer (`*.mdimporter`).
    case spotlightImporter

    /// `0x80` — File Provider extension (cloud storage drives, etc.).
    case fileProvider

    /// `0x800` — QuickLook preview / thumbnail extension (`*.appex`).
    case quicklook

    /// `0x10008` — legacy `SMLoginItem` agent that predates BTM
    /// migration. Apple keeps these around for backward compatibility.
    case legacyAgent

    /// Any raw type sfltool produces that we don't recognize. Raw
    /// text name preserved so detection rules can still match on it
    /// and future macOS additions don't lose data.
    case other(rawName: String)

    static func from(rawName: String, rawValue: Int) -> LoginItemKind {
        switch rawValue {
        case 0x2: return .app
        case 0x4: return .loginItem
        case 0x8: return .launchAgent
        case 0x10: return .launchDaemon
        case 0x40: return .spotlightImporter
        case 0x80: return .fileProvider
        case 0x800: return .quicklook
        case 0x10008: return .legacyAgent
        default: return .other(rawName: rawName)
        }
    }
}

/// BTM disposition bitfield — `Disposition: [enabled, allowed, notified] (0xN)`
/// in `sfltool dumpbtm` output. The bits surface in the raw text in the
/// order this `OptionSet` defines them; bit values pinned from the
/// observed sfltool output (0x1 = enabled, 0x2 = allowed, 0x8 = notified).
public struct LoginItemDisposition: OptionSet, Sendable, Equatable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// Bit `0x1`. `false` means the user has disabled the item.
    public static let enabled = LoginItemDisposition(rawValue: 0x01)

    /// Bit `0x2`. `false` means the item is blocked by policy (MDM
    /// configuration profile, etc.). Most items have this set.
    public static let allowed = LoginItemDisposition(rawValue: 0x02)

    /// Bit `0x8`. `true` means BTM has surfaced the item in the
    /// "Background Items added" Notification Center alert to the user.
    public static let notified = LoginItemDisposition(rawValue: 0x08)

    /// Stable lowercase rendering for display (e.g.
    /// `"enabled, allowed, notified"`). Matches the textual form
    /// `sfltool` produces.
    public var symbolicForm: String {
        var parts: [String] = []
        parts.append(contains(.enabled) ? "enabled" : "disabled")
        parts.append(contains(.allowed) ? "allowed" : "blocked")
        parts.append(contains(.notified) ? "notified" : "not notified")
        return parts.joined(separator: ", ")
    }
}
