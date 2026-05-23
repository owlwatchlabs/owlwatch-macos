import Foundation

/// One match of one rule against one item in a snapshot.
///
/// Findings are returned in evaluation order: rules execute in the
/// order they were loaded, items execute in the order the data source
/// produces them. Callers that need stable ordering across runs sort
/// by ``ruleID`` then ``targetID``.
public struct Finding: Sendable, Equatable {
    public let ruleID: String
    public let ruleName: String
    public let mitre: String?
    public let severity: Severity
    public let source: RuleSource

    /// Per-item identifier (process PID, plist path, login item UUID).
    /// Stable for the run; not stable across runs for short-lived
    /// items (a process re-execs and gets a new PID).
    public let targetID: String

    /// Fields named in the rule's `evidence:` list, populated with the
    /// matching item's value. Missing fields become the string
    /// `"(missing)"`.
    public let evidence: [String: String]

    /// When this finding was produced.
    public let scannedAt: Date

    public init(
        ruleID: String,
        ruleName: String,
        mitre: String? = nil,
        severity: Severity,
        source: RuleSource,
        targetID: String,
        evidence: [String: String] = [:],
        scannedAt: Date
    ) {
        self.ruleID = ruleID
        self.ruleName = ruleName
        self.mitre = mitre
        self.severity = severity
        self.source = source
        self.targetID = targetID
        self.evidence = evidence
        self.scannedAt = scannedAt
    }
}

/// Aggregate result of one scan. Callers iterate ``findings`` for the
/// detection output and read the metadata fields for run-level info.
public struct ScanReport: Sendable, Equatable {
    public let findings: [Finding]
    public let rulesEvaluated: Int
    public let itemsEvaluated: Int
    public let scannedAt: Date
    public let elapsed: TimeInterval

    public init(
        findings: [Finding],
        rulesEvaluated: Int,
        itemsEvaluated: Int,
        scannedAt: Date,
        elapsed: TimeInterval
    ) {
        self.findings = findings
        self.rulesEvaluated = rulesEvaluated
        self.itemsEvaluated = itemsEvaluated
        self.scannedAt = scannedAt
        self.elapsed = elapsed
    }
}
