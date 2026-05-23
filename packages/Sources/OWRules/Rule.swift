import Foundation

/// A single detection rule, parsed from one YAML document.
///
/// The YAML shape is documented in ADR-0004 and validated against
/// `docs/rules/rule-schema.json` at load time. The in-Swift `Rule`
/// matches the schema field for field; rule authors who pass schema
/// validation will pass Swift decoding.
public struct Rule: Sendable, Equatable {
    /// Stable identifier — conventionally `T<MITRE-ID>-<slug>` (e.g.
    /// `T1546.004-launchagent-in-downloads`). Required.
    public let id: String

    /// Short human-readable headline shown in finding output.
    public let name: String

    /// Long-form explanation of what the rule detects and why. Often
    /// references threat actors, intrusion sets, or specific malware
    /// families. May be `nil` for terse rules.
    public let description: String?

    /// MITRE ATT&CK technique ID this rule corresponds to (e.g.
    /// `T1546.004`). Optional — not every rule maps to a single
    /// technique.
    public let mitre: String?

    /// Severity of the rule's findings. Always set; defaults are
    /// applied at load time if the YAML omits the field.
    public let severity: Severity

    /// Which data source this rule iterates over.
    public let source: RuleSource

    /// Per-field predicates, ANDed together. Empty match dictionary
    /// matches every item in the source — useful for catch-all rules
    /// (rare).
    public let match: [String: Predicate]

    /// Names of fields to include in the finding's `evidence`
    /// dictionary. The evaluator reads each named field on the
    /// matching item and copies its string form into the finding.
    /// Empty array means no evidence beyond the rule + target ID.
    public let evidence: [String]

    /// Absolute path to the YAML file this rule was loaded from.
    /// Populated by the loader; used in error messages.
    public let sourceURL: URL?

    public init(
        id: String,
        name: String,
        description: String? = nil,
        mitre: String? = nil,
        severity: Severity,
        source: RuleSource,
        match: [String: Predicate] = [:],
        evidence: [String] = [],
        sourceURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.mitre = mitre
        self.severity = severity
        self.source = source
        self.match = match
        self.evidence = evidence
        self.sourceURL = sourceURL
    }
}
