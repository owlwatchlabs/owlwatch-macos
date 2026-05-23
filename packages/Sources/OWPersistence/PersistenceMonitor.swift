import CoreServices
import Darwin
import Foundation

extension OWPersistence {
    /// Default set of paths the monitor watches when no override is
    /// passed. Mirrors the M5 snapshot scopes — LaunchAgents /
    /// LaunchDaemons in every standard location, the System Extensions
    /// registry, kext directories, and the loginwindow preference
    /// plists.
    ///
    /// `/System/Library/LaunchDaemons` and `/System/Library/LaunchAgents`
    /// are included because mutations there (SIP-protected; nominally
    /// impossible) would be tier-1 alert signal. The cost of including
    /// them is negligible — FSEvents on a quiet directory emits no
    /// events.
    public static var defaultMonitorPaths: [String] {
        let home = NSHomeDirectory() as NSString
        return [
            "/System/Library/LaunchDaemons",
            "/System/Library/LaunchAgents",
            "/Library/LaunchDaemons",
            "/Library/LaunchAgents",
            home.appendingPathComponent("Library/LaunchAgents"),
            "/Library/SystemExtensions",
            "/Library/Extensions",
            "/Library/Preferences/com.apple.loginwindow.plist",
            home.appendingPathComponent("Library/Preferences/com.apple.loginwindow.plist")
        ]
    }

    /// Subscribe to filesystem events on every persistence-relevant
    /// path on the box. Returns an `AsyncThrowingStream` that yields
    /// one ``PersistenceMutation`` per FSEvents callback record.
    ///
    /// The underlying `FSEventStream` runs on a private dispatch queue
    /// and starts emitting events immediately (no historical replay
    /// — we pass `kFSEventStreamEventIdSinceNow`). Cancellation:
    /// the stream's `onTermination` callback stops and releases the
    /// event stream.
    ///
    /// - Parameter paths: directories / files to watch. Defaults to
    ///   ``defaultMonitorPaths``. Non-existent paths are tolerated;
    ///   FSEvents will pick them up if they appear later.
    /// - Parameter latency: FSEvents coalescing window in seconds.
    ///   `0.0` is "emit immediately, batch nothing" (max responsiveness,
    ///   higher overhead); `0.5` is the default and a reasonable
    ///   trade-off for security-relevant paths that don't churn.
    public static func monitor(
        paths: [String] = defaultMonitorPaths,
        latency: TimeInterval = 0.5
    ) -> AsyncThrowingStream<PersistenceMutation, Error> {
        AsyncThrowingStream { continuation in
            let runner = MonitorRunner(paths: paths, latency: latency, continuation: continuation)
            do {
                try runner.start()
            } catch {
                continuation.finish(throwing: error)
                return
            }
            continuation.onTermination = { _ in
                runner.stop()
            }
        }
    }

    /// Same FSEvents subscription as ``monitor(paths:latency:)``, but
    /// each yielded ``PersistenceMutation`` is wrapped in an
    /// ``EnrichedMutation`` whose typed payload reflects the *contents*
    /// of the changed file.
    ///
    /// For LaunchAgent / LaunchDaemon plist mutations (excluding
    /// removals), the parsed ``LaunchService`` is attached. For
    /// `com.apple.loginwindow.plist` mutations, the resulting
    /// ``LoginLogoutHook`` entries are attached. Removed files have
    /// no readable content; the enrichment fields stay `nil`.
    ///
    /// Enrichment runs synchronously on the same dispatch queue as the
    /// raw event delivery — parsing a launchd plist is on the order of
    /// hundreds of microseconds, well inside the FSEvents latency
    /// window. If a watched directory ever sees enough write volume
    /// for the parse cost to matter, drop back to the raw
    /// ``monitor(paths:latency:)`` API.
    public static func monitorEnriched(
        paths: [String] = defaultMonitorPaths,
        latency: TimeInterval = 0.5
    ) -> AsyncThrowingStream<EnrichedMutation, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await mutation in monitor(paths: paths, latency: latency) {
                        let enriched = enrich(mutation: mutation)
                        continuation.yield(enriched)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

// MARK: - Enrichment

/// Wrap a raw ``PersistenceMutation`` into an ``EnrichedMutation``.
/// Reads the file at ``mutation.path`` when the event isn't a
/// removal, parses it with the appropriate M5 parser based on the
/// scope, and attaches the result. Failures fall through to a
/// payload-less enriched record — never throws.
internal func enrich(mutation: PersistenceMutation) -> EnrichedMutation {
    // Removed files have no content to read; surface the raw event
    // without payload.
    guard mutation.kind != .removed else {
        return EnrichedMutation(mutation: mutation)
    }

    switch mutation.scope {
    case .platformLaunchd, .systemLaunchd, .userLaunchd:
        let scope = mapToLaunchScope(mutation: mutation)
        let service = parseLaunchService(
            at: mutation.path,
            scope: scope,
            centralDisabledMap: [:]
        )
        return EnrichedMutation(mutation: mutation, launchService: service)

    case .loginwindowPlist:
        let scope: HookScope = mutation.path.hasPrefix("/Library/")
            ? .system
            : .user
        let hooks = parseLoginLogoutHooks(at: mutation.path, scope: scope)
        return EnrichedMutation(mutation: mutation, hooks: hooks)

    case .systemExtensionsRegistry, .kernelExtensions, .other:
        // System Extensions / kexts have richer payloads (db.plist
        // structure, kext bundle structure) that don't map to a
        // single value type per mutation event — surface the raw
        // mutation and let the caller call OWPersistence.kernel/
        // systemExtensions() if they need the current snapshot.
        return EnrichedMutation(mutation: mutation)
    }
}

/// Pick the M5 ``LaunchScope`` matching this mutation's path. We use
/// the path prefix directly rather than the ``MutationScope`` enum
/// because ``MutationScope`` collapses `LaunchDaemons` and
/// `LaunchAgents` under one case (`.systemLaunchd`, etc.), but
/// ``LaunchScope`` distinguishes daemon-vs-agent. Disabled-state
/// resolution needs the distinction (daemon disabled-lists live at
/// a different path than agent lists).
private func mapToLaunchScope(mutation: PersistenceMutation) -> LaunchScope {
    let path = mutation.path
    if path.hasPrefix("/System/Library/LaunchDaemons") { return .platformDaemon }
    if path.hasPrefix("/System/Library/LaunchAgents") { return .platformAgent }
    if path.hasPrefix("/Library/LaunchDaemons") { return .systemDaemon }
    if path.hasPrefix("/Library/LaunchAgents") { return .systemAgent }
    return .userAgent
}

/// Reference-typed holder for the `FSEventStreamRef` and the
/// continuation we yield into. Lives as long as the monitor stream
/// has subscribers; teardown happens via ``stop()``.
///
/// Marked `@unchecked Sendable` because the underlying
/// `FSEventStreamRef` is a CoreFoundation object and the dispatch
/// queue serializes callback invocations onto a single thread —
/// only one writer can touch the state at any moment. The closure
/// captures don't escape that queue.
private final class MonitorRunner: @unchecked Sendable {
    private let paths: [String]
    private let latency: TimeInterval
    private let continuation: AsyncThrowingStream<PersistenceMutation, Error>.Continuation
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.owlwatchlabs.owlwatch.persistence-monitor")

    init(
        paths: [String],
        latency: TimeInterval,
        continuation: AsyncThrowingStream<PersistenceMutation, Error>.Continuation
    ) {
        self.paths = paths
        self.latency = latency
        self.continuation = continuation
    }

    func start() throws {
        let pathsCF = paths as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagUseCFTypes
        )
        guard let createdStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (_, info, count, paths, flags, ids) in
                guard let info else { return }
                let runner = Unmanaged<MonitorRunner>.fromOpaque(info).takeUnretainedValue()
                runner.dispatch(eventCount: count, paths: paths, flags: flags, ids: ids)
            },
            &context,
            pathsCF,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            throw OWPersistenceMonitorError.unableToCreateStream(paths: paths)
        }
        FSEventStreamSetDispatchQueue(createdStream, queue)
        guard FSEventStreamStart(createdStream) else {
            FSEventStreamInvalidate(createdStream)
            FSEventStreamRelease(createdStream)
            throw OWPersistenceMonitorError.streamFailedToStart
        }
        stream = createdStream
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, let stream = self.stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            self.continuation.finish()
        }
    }

    /// FSEvents callback fanout. Decodes each event into a
    /// `PersistenceMutation` and yields it into the continuation.
    func dispatch(
        eventCount: Int,
        paths: UnsafeRawPointer,
        flags: UnsafePointer<FSEventStreamEventFlags>,
        ids: UnsafePointer<FSEventStreamEventId>
    ) {
        // With kFSEventStreamCreateFlagUseCFTypes, the paths pointer is
        // an unsafe pointer to a CFArrayRef of CFStringRef.
        let pathArray = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String]
        guard let pathArray else { return }

        let now = Date()
        for index in 0..<eventCount {
            let path = pathArray[index]
            let eventFlags = flags[index]
            let kind = classifyKind(flags: eventFlags)
            let scope = classifyScope(path: path)
            let mutation = PersistenceMutation(
                path: path,
                kind: kind,
                scope: scope,
                timestamp: now,
                eventID: ids[index]
            )
            continuation.yield(mutation)
        }
    }
}

/// Choose the single most-descriptive ``MutationKind`` for an event
/// whose flag bitfield may set several flags at once. Order matters:
/// "added" wins over "modified" wins over "metadataChanged", because
/// the more disruptive operation is the one a detection rule wants.
internal func classifyKind(flags: FSEventStreamEventFlags) -> MutationKind {
    let bits = UInt32(flags)
    if bits & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 { return .removed }
    if bits & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 { return .renamed }
    if bits & UInt32(kFSEventStreamEventFlagItemCreated) != 0 { return .added }
    if bits & UInt32(kFSEventStreamEventFlagItemModified) != 0 { return .modified }
    if bits & UInt32(kFSEventStreamEventFlagItemXattrMod) != 0 { return .xattrChanged }
    if bits & UInt32(kFSEventStreamEventFlagItemInodeMetaMod) != 0 { return .metadataChanged }
    return .modified  // safe fallback for "something changed"
}

/// Classify the watched path into a ``MutationScope``. Done with
/// `hasPrefix` checks rather than a regex / pattern table because
/// the prefix list is small, fixed, and ordered (the more specific
/// `/Library/...` paths must be checked before `/System/Library/...`
/// — but in practice the strings don't collide, so either order works).
internal func classifyScope(path: String) -> MutationScope {
    if path.hasPrefix("/System/Library/LaunchDaemons") ||
       path.hasPrefix("/System/Library/LaunchAgents") {
        return .platformLaunchd
    }
    if path.hasPrefix("/Library/LaunchDaemons") ||
       path.hasPrefix("/Library/LaunchAgents") {
        return .systemLaunchd
    }
    if path.contains("/Library/LaunchAgents") {
        return .userLaunchd
    }
    if path.hasPrefix("/Library/SystemExtensions") {
        return .systemExtensionsRegistry
    }
    if path.hasPrefix("/System/Library/Extensions") ||
       path.hasPrefix("/Library/Extensions") {
        return .kernelExtensions
    }
    if path.hasSuffix("com.apple.loginwindow.plist") {
        return .loginwindowPlist
    }
    return .other
}
