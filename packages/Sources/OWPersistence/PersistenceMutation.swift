import Foundation

/// A single filesystem mutation observed at one of Owlwatch's watched
/// persistence locations.
///
/// `PersistenceMutation` is the live counterpart to the snapshot types
/// in M5 (``LaunchService`` et al.): where the snapshot answers
/// *"what is installed right now?"*, the mutation stream answers
/// *"what just changed?"*. It's emitted by
/// ``OWPersistence/OWPersistence/monitor()`` as an
/// `AsyncThrowingStream`, one record per change.
///
/// The fields are intentionally minimal — just enough to drive a
/// detection rule or audit-log entry. Enrichment (parsing the changed
/// plist and embedding the resulting `LaunchService` / `LoginItem`)
/// lands in M10.2.
public struct PersistenceMutation: Sendable, Equatable, Hashable {
    /// Filesystem path the mutation applies to. For LaunchAgent /
    /// LaunchDaemon changes this is the `.plist` path; for
    /// directory-level events (rare with file-level FSEvents flags) it
    /// can be the parent directory.
    public let path: String

    /// What happened — file appeared, was modified, was removed, etc.
    public let kind: MutationKind

    /// Which scope the path lives in. Lets callers ignore platform
    /// (`/System/Library/*`) changes while still alerting on the
    /// third-party (`/Library/*`) and per-user (`~/Library/*`) trees.
    public let scope: MutationScope

    /// Wall-clock time the event was observed (FSEvents callback time,
    /// not the kernel event time — those differ by milliseconds).
    public let timestamp: Date

    /// FSEvent ID assigned by the kernel for this event. Stable per
    /// boot; lets callers correlate events emitted by the same
    /// underlying mutation when multiple flag bits fire (e.g. a
    /// `creat` + `setxattr` close in time).
    public let eventID: UInt64

    public init(
        path: String,
        kind: MutationKind,
        scope: MutationScope,
        timestamp: Date,
        eventID: UInt64
    ) {
        self.path = path
        self.kind = kind
        self.scope = scope
        self.timestamp = timestamp
        self.eventID = eventID
    }
}

/// What kind of change FSEvents reported. Derived from the
/// `FSEventStreamEventFlags` bitfield on each event; one event may
/// fire with several flag bits set (e.g. created + modified within
/// the same batch), in which case the most descriptive kind wins —
/// ``added`` over ``modified`` over ``metadataChanged``.
public enum MutationKind: String, Sendable, Equatable, Hashable, CaseIterable {
    /// File or directory came into existence
    /// (`kFSEventStreamEventFlagItemCreated`).
    case added

    /// File content was written to
    /// (`kFSEventStreamEventFlagItemModified`).
    case modified

    /// File or directory was unlinked
    /// (`kFSEventStreamEventFlagItemRemoved`).
    case removed

    /// File was renamed in or out of the watched scope
    /// (`kFSEventStreamEventFlagItemRenamed`).
    case renamed

    /// Extended attribute set / cleared
    /// (`kFSEventStreamEventFlagItemXattrMod`) — particularly relevant
    /// for `com.apple.quarantine` removal as a Gatekeeper-bypass
    /// signal.
    case xattrChanged

    /// inode metadata (ownership, mode, timestamps) changed
    /// (`kFSEventStreamEventFlagItemInodeMetaMod`).
    case metadataChanged
}

/// Which persistence directory hierarchy the mutation lives in.
/// Mirrors ``LaunchScope`` but spans all M5 sources, not just
/// LaunchAgents / LaunchDaemons.
public enum MutationScope: String, Sendable, Equatable, Hashable, CaseIterable {
    /// `/System/Library/LaunchDaemons` or `/System/Library/LaunchAgents`.
    /// SIP-protected; mutations here are rare and high-priority.
    case platformLaunchd

    /// `/Library/LaunchDaemons` or `/Library/LaunchAgents`. Admin /
    /// installer writes.
    case systemLaunchd

    /// `~/Library/LaunchAgents`. Per-user; the most common malware
    /// persistence target on macOS.
    case userLaunchd

    /// `/Library/SystemExtensions/` registry directory.
    case systemExtensionsRegistry

    /// `/System/Library/Extensions` or `/Library/Extensions` — kext
    /// bundle directories.
    case kernelExtensions

    /// `/Library/Preferences/com.apple.loginwindow.plist` or
    /// `~/Library/Preferences/com.apple.loginwindow.plist`.
    case loginwindowPlist

    /// Some other path the monitor was configured to watch but doesn't
    /// recognize. Raw path preserved in
    /// ``PersistenceMutation/path``.
    case other
}

/// Errors thrown by ``OWPersistence/OWPersistence/monitor()``.
public enum OWPersistenceMonitorError: Error, Sendable, Equatable {
    /// `FSEventStreamCreate` returned `nil` — most often because every
    /// path in the watch set was unreadable or didn't exist. The list
    /// of paths we tried is preserved for diagnostics.
    case unableToCreateStream(paths: [String])

    /// `FSEventStreamStart` returned `false`. Rare — usually a
    /// permissions issue or a TCC denial.
    case streamFailedToStart
}
