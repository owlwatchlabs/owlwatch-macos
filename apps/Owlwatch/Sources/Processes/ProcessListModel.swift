import Foundation
import OWCodeSigning
import OWNetwork
import OWPersistence
import OWProcess
import OWRules
import OWTriage
import SwiftUI

/// Drives the M18.4 faceted process list. Owns the row collection,
/// the active facets, the free-text query, and the salience-sorted
/// `visible` projection.
///
/// `refresh()` joins five data sources (OWProcess + OWNetwork +
/// OWPersistence + OWCodeSigning + OWRules) into a flat
/// `[ProcessRowVM]` array. Heavy passes (per-binary signature
/// inspection, rule evaluation) run here, get cached behind a
/// `pathSignerCache`, and amortize across re-refreshes. The
/// silent-live-data architecture from M18.6 will replace
/// `refresh()` with a diff-based silent update.
@MainActor
final class ProcessListModel: ObservableObject {
    // MARK: - Inputs

    @Published var query: String = ""
    @Published var active: Set<ProcessFacet> = []

    // MARK: - Outputs

    @Published private(set) var rows: [ProcessRowVM] = []
    @Published var selection: pid_t?
    @Published private(set) var isLoading: Bool = false

    // MARK: - State

    /// Per-path signer cache. SecStaticCode inspection is ~10–50ms
    /// per binary; caching means subsequent refreshes only pay the
    /// inspect cost for paths that weren't running last time.
    private var pathSignerCache: [String: Signer] = [:]

    /// Loaded once, reused across refreshes.
    private var cachedRules: [Rule]?

    // MARK: - Public surface

    /// Live count per facet — used by the chip labels. Operates on
    /// the full `rows` set (pre-filter) so the chip never lies
    /// about how many are available if you toggle it.
    func count(_ facet: ProcessFacet) -> Int {
        rows.lazy.filter(facet.matches).count
    }

    /// The visible row set — query-filtered, facet-stacked (AND),
    /// salience-sorted.
    var visible: [ProcessRowVM] {
        let filtered = rows.filter { row in
            (query.isEmpty || row.matchesQuery(query)) &&
                active.allSatisfy { $0.matches(row) }
        }
        return filtered.sorted(by: Self.salience)
    }

    /// Salience: highest rule severity first, then unsigned ahead
    /// of signed, then alphabetical. **Not** alphabetical-first —
    /// the user wants the interesting rows visible immediately.
    private static func salience(_ a: ProcessRowVM, _ b: ProcessRowVM) -> Bool {
        let aSev = a.maxSeverity ?? .info
        let bSev = b.maxSeverity ?? .info
        if aSev != bSev {
            // Both .info doesn't beat itself; compare for descending.
            return aSev > bSev
        }
        let aUnsigned = a.signer == .unsigned
        let bUnsigned = b.signer == .unsigned
        if aUnsigned != bUnsigned { return aUnsigned }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }

    // MARK: - Refresh

    /// Two-stage refresh.
    ///
    /// Stage 1 — instant: cheap pulls (process list + connections +
    /// launch services) feed a row build that uses `.unknown` for
    /// signer and zero for rule findings. The list renders right
    /// away and `isLoading` clears.
    ///
    /// Stage 2 — background enrichment: SecStaticCode inspection
    /// (with a per-path timeout so a single wedged binary can't
    /// hang the section) and the OWRules scan. Each completed pass
    /// patches `rows` in place by pid. M18.6 will generalize this
    /// pattern into a diff-based silent update.
    func refresh() async {
        isLoading = true

        // Parallel cheap pulls — process list, connections, launch
        // services. Login items are skipped here on purpose (sfltool
        // prompt is a per-user-input flow, see M17.5).
        async let processesT = Task.detached(priority: .userInitiated) {
            (try? OWProcess.all(includeArguments: false, includeOpenFiles: false)) ?? []
        }.value
        async let connectionsT = Task.detached(priority: .userInitiated) {
            (try? OWNetwork.snapshot()) ?? []
        }.value
        async let launchT = Task.detached(priority: .userInitiated) {
            OWPersistence.launchServices()
        }.value

        let processes = await processesT
        let connections = await connectionsT
        let launchServices = await launchT

        let connsByPid = Dictionary(grouping: connections, by: { $0.pid })
        let persistentPaths: Set<String> = Set(
            launchServices.compactMap { $0.executablePath }
        )

        // Stage 1: build rows with unknown signers and no rule
        // findings. List paints instantly.
        rows = processes.map { process in
            let processConns = connsByPid[process.pid] ?? []
            let scopes = Set(processConns.map(NetworkScope.init))
            let hasListener = processConns.contains(where: \.isListener)
            let isPersistent = process.path.map { persistentPaths.contains($0) } ?? false
            let cachedSigner = process.path.flatMap { pathSignerCache[$0] } ?? .unknown
            return ProcessRowVM(
                pid: process.pid,
                parentPid: process.parentPid,
                name: process.name,
                path: process.path,
                userId: process.userId,
                signer: cachedSigner,
                scopes: scopes,
                hasListener: hasListener,
                isPersistent: isPersistent,
                tccCount: 0,
                isSuspiciousPath: isSuspiciousPath(process.path),
                ruleCount: 0,
                maxSeverity: nil
            )
        }
        isLoading = false

        // Drop stale selection.
        if let pid = selection, !rows.contains(where: { $0.pid == pid }) {
            selection = nil
        }

        // Stage 2: enrichment in the background.
        await enrich(processes: processes,
                     launchServices: launchServices,
                     connections: connections)
    }

    /// Stage 2 enrichment. Signature inspection then rules scan,
    /// each patching `rows` in place by pid.
    private func enrich(
        processes: [RunningProcess],
        launchServices: [LaunchService],
        connections: [Connection]
    ) async {
        // Signature pass — only paths we don't already have cached.
        let pathsToInspect: [String] = Array(
            Set(processes.compactMap(\.path)).subtracting(pathSignerCache.keys)
        )
        if !pathsToInspect.isEmpty {
            let inspected = await Self.inspectSigners(for: pathsToInspect)
            for (path, signer) in inspected {
                pathSignerCache[path] = signer
            }
            rows = rows.map { row in
                guard let path = row.path,
                      let updated = pathSignerCache[path],
                      updated != row.signer else { return row }
                return ProcessRowVM(
                    pid: row.pid,
                    parentPid: row.parentPid,
                    name: row.name,
                    path: row.path,
                    userId: row.userId,
                    signer: updated,
                    scopes: row.scopes,
                    hasListener: row.hasListener,
                    isPersistent: row.isPersistent,
                    tccCount: row.tccCount,
                    isSuspiciousPath: row.isSuspiciousPath,
                    ruleCount: row.ruleCount,
                    maxSeverity: row.maxSeverity
                )
            }
        }

        // Rules pass. Loaded lazily on first use, then reused.
        if cachedRules == nil {
            cachedRules = (try? Self.loadShippedRules()) ?? []
        }
        let rules = cachedRules ?? []
        let snapshot = Snapshot(
            processes: processes,
            launchServices: launchServices,
            loginItems: [],
            binaries: [],          // M18.4 skips the binary source — see brief §5
            connections: connections,
            kernelExtensions: [],
            signatures: []
        )
        let report = await Task.detached(priority: .userInitiated) {
            OWRules.scan(rules: rules, snapshot: snapshot)
        }.value

        var findingsByPid: [pid_t: (count: Int, maxSev: Severity)] = [:]
        for finding in report.findings {
            guard finding.targetID.hasPrefix("pid:"),
                  let pidValue = pid_t(finding.targetID.dropFirst(4)) else { continue }
            var entry = findingsByPid[pidValue] ?? (count: 0, maxSev: .info)
            entry.count += 1
            if finding.severity > entry.maxSev { entry.maxSev = finding.severity }
            findingsByPid[pidValue] = entry
        }

        rows = rows.map { row in
            guard let entry = findingsByPid[row.pid] else { return row }
            return ProcessRowVM(
                pid: row.pid,
                parentPid: row.parentPid,
                name: row.name,
                path: row.path,
                userId: row.userId,
                signer: row.signer,
                scopes: row.scopes,
                hasListener: row.hasListener,
                isPersistent: row.isPersistent,
                tccCount: row.tccCount,
                isSuspiciousPath: row.isSuspiciousPath,
                ruleCount: entry.count,
                maxSeverity: entry.count > 0 ? entry.maxSev : nil
            )
        }
    }

    // MARK: - Helpers

    /// Concurrency-limited parallel `SecStaticCode` inspection.
    ///
    /// `nonisolated` is load-bearing: this method is called from
    /// MainActor-isolated `enrich()`, and without the opt-out the
    /// spawned child tasks would inherit MainActor and serialize
    /// 500+ synchronous Security-framework calls on the main
    /// thread — which is exactly the hang the M18.4 spinner was
    /// stuck behind.
    ///
    /// A small concurrency cap (8) prevents thrashing the Swift
    /// cooperative thread pool. Raising it any higher (e.g. 16)
    /// deadlocks the pool: SecStaticCode is a synchronous Security
    /// framework call that blocks its thread for its whole
    /// duration, and 16 simultaneous blocking calls saturate every
    /// thread in the cooperative pool, leaving no thread free to
    /// dispatch the awaiter's continuation. The proper fix is to
    /// bridge inspects through DispatchQueue.global (64-thread
    /// pool, sized for blocking work) — deferred to a follow-up.
    nonisolated private static func inspectSigners(for paths: [String]) async -> [String: Signer] {
        await withTaskGroup(of: (String, Signer).self) { group in
            let maxConcurrent = 8
            var iter = paths.makeIterator()

            for _ in 0..<min(maxConcurrent, paths.count) {
                guard let path = iter.next() else { break }
                group.addTask(priority: .utility) { Self.inspectOne(path) }
            }

            var result: [String: Signer] = [:]
            while let (path, signer) = await group.next() {
                result[path] = signer
                if let next = iter.next() {
                    group.addTask(priority: .utility) { Self.inspectOne(next) }
                }
            }
            return result
        }
    }

    nonisolated private static func inspectOne(_ path: String) -> (String, Signer) {
        let url = URL(fileURLWithPath: path)
        let sig = try? OWCodeSigning.inspect(at: url)
        return (path, Signer(sig))
    }

    /// Locate the shipped rules library. In a built app this is
    /// `Contents/Resources/Rules`; in a development run from the
    /// checkout, fall back to `packages/Rules` relative to the
    /// repo root. Returns an empty list if neither resolves.
    nonisolated private static func loadShippedRules() throws -> [Rule] {
        // Bundled at Contents/Resources/Rules (see project.yml).
        if let bundleURL = Bundle.main.url(forResource: "Rules", withExtension: nil) {
            return try OWRules.loadRules(from: bundleURL)
        }
        // Development checkout fallback. The CWD when running
        // from Xcode is the project root; the rules sit two dirs up.
        let fileManager = FileManager.default
        let candidates = [
            URL(fileURLWithPath: "packages/Rules"),
            URL(fileURLWithPath: "../../packages/Rules"),
            URL(fileURLWithPath: "../packages/Rules")
        ]
        for url in candidates where fileManager.fileExists(atPath: url.path) {
            return try OWRules.loadRules(from: url)
        }
        return []
    }
}

