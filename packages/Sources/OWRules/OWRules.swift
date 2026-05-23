import Foundation
import OWBinary
import OWPersistence
import OWProcess

/// Owlwatch's detection rules engine.
///
/// `OWRules` evaluates declarative YAML rules (see ADR-0004) against
/// snapshot readings of the data sources M1–M11 ship. The M13.1
/// surface is intentionally narrow: load rules from disk, capture a
/// snapshot, evaluate, emit findings. Streaming evaluation, schema
/// evolution, and the rule library expansion land in later slices.
///
/// ## Usage
///
/// ```swift
/// let rules = try OWRules.loadRules(from: rulesURL)
/// let snapshot = OWRules.captureSnapshot()
/// let report = OWRules.scan(rules: rules, snapshot: snapshot)
/// for finding in report.findings {
///     print("[\(finding.severity.displayName)] \(finding.ruleID): \(finding.targetID)")
/// }
/// ```
public enum OWRules {
    /// Parse one rule from a YAML file.
    public static func loadRule(from url: URL) throws -> Rule {
        try RuleLoader.loadRule(from: url)
    }

    /// Parse every `.yml` / `.yaml` rule in `directory`. Returns rules
    /// in filename order; duplicate IDs across files raise
    /// ``OWRulesError/duplicateRuleID(id:urls:)``.
    public static func loadRules(from directory: URL) throws -> [Rule] {
        try RuleLoader.loadRules(from: directory)
    }

    /// Capture a fresh snapshot of every data source the evaluator
    /// can consume.
    ///
    /// - Parameter includeArguments: forwarded to ``OWProcess/all(includeArguments:includeOpenFiles:)``.
    ///   Required for any rule that matches on `arguments`; rules that
    ///   only need `pid` / `name` / `path` can pass `false` for speed.
    /// - Parameter includeBinaries: when `true`, parses each unique
    ///   process executable via `OWBinary` and builds a
    ///   ``BinarySummary`` per binary. Costly — a typical Mac runs
    ///   ~300 unique executables and parsing each is a millisecond or
    ///   so. The convenience ``scan(rules:)`` overload sets this
    ///   based on whether any loaded rule needs the binary source.
    public static func captureSnapshot(
        includeArguments: Bool = true,
        includeBinaries: Bool = true
    ) throws -> Snapshot {
        let processes = try OWProcess.all(
            includeArguments: includeArguments,
            includeOpenFiles: false
        )
        let services = OWPersistence.launchServices()
        let items = OWPersistence.loginItems()
        let binaries = includeBinaries
            ? captureBinaries(from: processes)
            : []
        return Snapshot(
            processes: processes,
            launchServices: services,
            loginItems: items,
            binaries: binaries
        )
    }

    /// Parse every unique executable path in `processes` into a
    /// ``BinarySummary``. Paths that fail to parse (permission
    /// denied, non-Mach-O, malformed) are silently skipped — a
    /// failed parse is not a finding by itself, and the noise would
    /// dominate the report.
    private static func captureBinaries(from processes: [RunningProcess]) -> [BinarySummary] {
        var seen: Set<String> = []
        var summaries: [BinarySummary] = []
        for process in processes {
            guard let path = process.path, !seen.contains(path) else { continue }
            seen.insert(path)
            let url = URL(fileURLWithPath: path)
            guard let binary = try? OWBinary.parse(at: url, includeSymbols: false) else {
                continue
            }
            summaries.append(BinarySummary.make(from: binary))
        }
        return summaries
    }

    /// Evaluate `rules` against `snapshot`. Returns a ``ScanReport``
    /// with one ``Finding`` per match. Synchronous and pure — safe to
    /// call from any actor context.
    public static func scan(rules: [Rule], snapshot: Snapshot) -> ScanReport {
        Evaluator.evaluate(rules: rules, snapshot: snapshot)
    }

    /// Convenience: capture a fresh snapshot and evaluate `rules`
    /// against it in one call. Skips binary parsing when no loaded
    /// rule targets the `binary` source — keeps simple `process` /
    /// `launch_service` / `login_item` scans cheap.
    public static func scan(rules: [Rule]) throws -> ScanReport {
        let needsBinaries = rules.contains { $0.source == .binary }
        let needsArguments = rules.contains { rule in
            rule.source == .process && (
                rule.match.keys.contains("arguments") || rule.evidence.contains("arguments")
            )
        }
        let snapshot = try captureSnapshot(
            includeArguments: needsArguments,
            includeBinaries: needsBinaries
        )
        return scan(rules: rules, snapshot: snapshot)
    }
}
