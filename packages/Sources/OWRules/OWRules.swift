import Foundation
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
    public static func captureSnapshot(includeArguments: Bool = true) throws -> Snapshot {
        let processes = try OWProcess.all(
            includeArguments: includeArguments,
            includeOpenFiles: false
        )
        let services = OWPersistence.launchServices()
        let items = OWPersistence.loginItems()
        return Snapshot(
            processes: processes,
            launchServices: services,
            loginItems: items
        )
    }

    /// Evaluate `rules` against `snapshot`. Returns a ``ScanReport``
    /// with one ``Finding`` per match. Synchronous and pure — safe to
    /// call from any actor context.
    public static func scan(rules: [Rule], snapshot: Snapshot) -> ScanReport {
        Evaluator.evaluate(rules: rules, snapshot: snapshot)
    }

    /// Convenience: capture a fresh snapshot and evaluate `rules`
    /// against it in one call.
    public static func scan(rules: [Rule]) throws -> ScanReport {
        let snapshot = try captureSnapshot()
        return scan(rules: rules, snapshot: snapshot)
    }
}
