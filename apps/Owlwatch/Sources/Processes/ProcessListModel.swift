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

    /// Raw findings indexed by pid for the dossier (M18.5). Cleared
    /// at the start of each refresh and repopulated when stage 2
    /// finishes the OWRules scan. The row's `ruleCount` /
    /// `maxSeverity` are the summary; this dictionary is the detail.
    @Published private(set) var findingsByPid: [pid_t: [Finding]] = [:]

    // MARK: - State

    /// Per-path signer cache. SecStaticCode inspection is ~10–50ms
    /// per binary; caching means subsequent refreshes only pay the
    /// inspect cost for paths that weren't running last time.
    private var pathSignerCache: [String: Signer] = [:]

    /// Per-pid LaunchService matches — used by the dossier to render
    /// the "Launched by" section when a process is persistent.
    /// Repopulated each refresh from the launch-services snapshot.
    private var launchByPid: [pid_t: [LaunchService]] = [:]

    /// Per-pid connections — used by the dossier's Network preview
    /// card. Same data source the full Network section reads, just
    /// indexed for the per-process view.
    private var connectionsByPid: [pid_t: [Connection]] = [:]

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
        connectionsByPid = connsByPid
        let launchByPath = Dictionary(
            grouping: launchServices.filter { $0.executablePath != nil },
            by: { $0.executablePath! }
        )
        let persistentPaths: Set<String> = Set(launchByPath.keys)

        // Rebuild per-pid launch service index used by the dossier
        // (M18.5). Keyed by pid so the detail pane doesn't have to
        // re-scan all launch services.
        var byPid: [pid_t: [LaunchService]] = [:]
        for process in processes {
            if let path = process.path, let matches = launchByPath[path] {
                byPid[process.pid] = matches
            }
        }
        launchByPid = byPid
        // Findings are repopulated in stage 2; clear the stale view.
        findingsByPid = [:]

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

        var grouped: [pid_t: [Finding]] = [:]
        for finding in report.findings {
            guard finding.targetID.hasPrefix("pid:"),
                  let pidValue = pid_t(finding.targetID.dropFirst(4)) else { continue }
            grouped[pidValue, default: []].append(finding)
        }
        findingsByPid = grouped

        rows = rows.map { row in
            guard let findings = grouped[row.pid], !findings.isEmpty else { return row }
            let maxSev = findings.map(\.severity).max() ?? .info
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
                ruleCount: findings.count,
                maxSeverity: maxSev
            )
        }
    }

    // MARK: - Dossier accessors (M18.5)

    /// Rule findings for a given pid, sorted highest severity first.
    /// Empty for pids with no findings or before stage 2 enrichment
    /// completes.
    func findings(for pid: pid_t) -> [Finding] {
        (findingsByPid[pid] ?? []).sorted { $0.severity > $1.severity }
    }

    /// LaunchService entries whose executable path matches the given
    /// pid's process path. Used by the dossier's persistence section.
    func launchServices(for pid: pid_t) -> [LaunchService] {
        launchByPid[pid] ?? []
    }

    /// Connections owned by the given pid. Used by the dossier's
    /// Network preview card.
    func connections(for pid: pid_t) -> [Connection] {
        connectionsByPid[pid] ?? []
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

    /// Locate the shipped rules library. xcodegen's `name: Rules`
    /// flattens the contents into `Contents/Resources/` rather than
    /// nesting them under a `Rules/` subdir, so `Bundle.main.url(
    /// forResource: "Rules")` returns nil. Loading the entire
    /// `resourceURL` works because `OWRules.loadRules(from:)`
    /// already filters to `*.yml` / `*.yaml` and ignores everything
    /// else (icons, plists, etc.). Development checkout falls back
    /// to the source tree.
    nonisolated private static func loadShippedRules() throws -> [Rule] {
        if let resourceURL = Bundle.main.resourceURL {
            let rules = try OWRules.loadRules(from: resourceURL)
            if !rules.isEmpty { return rules }
        }
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

