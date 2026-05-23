import Foundation

/// A ``PersistenceMutation`` plus the parsed payload it refers to.
///
/// Where the raw stream from
/// ``OWPersistence/OWPersistence/monitor(paths:latency:)`` answers
/// "*what* changed at *what* path?", the enriched stream from
/// ``OWPersistence/OWPersistence/monitorEnriched(paths:latency:)``
/// answers the follow-up question detection rules actually care
/// about: "*what was in the file?*".
///
/// For a `LaunchAgent` / `LaunchDaemon` plist that was just added or
/// modified, ``launchService`` is populated with the parsed value.
/// For a `loginwindow.plist` that just changed, ``hooks`` carries the
/// resulting `LoginHook` / `LogoutHook` entries. Removed-file events
/// have no readable payload — both fields are `nil`.
public struct EnrichedMutation: Sendable, Equatable, Hashable {
    /// The raw filesystem event (path, kind, scope, timestamp, eventID).
    public let mutation: PersistenceMutation

    /// Parsed launchd service for `LaunchAgent` / `LaunchDaemon` paths.
    /// `nil` for non-launchd paths, removed-file events, or plists
    /// that didn't parse cleanly.
    public let launchService: LaunchService?

    /// Parsed login / logout hooks for `com.apple.loginwindow.plist`
    /// mutations. Empty array when the plist parses but contains no
    /// `LoginHook` / `LogoutHook` keys; `nil` for other scopes.
    public let hooks: [LoginLogoutHook]?

    public init(
        mutation: PersistenceMutation,
        launchService: LaunchService? = nil,
        hooks: [LoginLogoutHook]? = nil
    ) {
        self.mutation = mutation
        self.launchService = launchService
        self.hooks = hooks
    }

    /// `true` when the enrichment populated at least one typed
    /// payload field. Used by CLI / UI to decide whether to render
    /// the rich columns or just the raw mutation info.
    public var hasPayload: Bool {
        launchService != nil || (hooks?.isEmpty == false)
    }
}
