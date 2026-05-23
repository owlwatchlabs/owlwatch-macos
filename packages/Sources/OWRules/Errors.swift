import Foundation

/// Errors raised by the rules engine.
///
/// Loader errors carry the URL of the offending file so authors can
/// jump to the broken rule. Evaluator errors carry the rule ID since
/// the rule has already been parsed.
public enum OWRulesError: Error, Sendable, Equatable {
    /// The YAML at `url` failed to parse. `reason` carries the YAML
    /// library's error message.
    case yamlParseFailed(url: URL, reason: String)

    /// The YAML parsed but doesn't match the rule schema. `field` is
    /// the offending key (e.g. `severity`, `when.source`); `reason`
    /// explains what's wrong.
    case schemaViolation(url: URL, field: String, reason: String)

    /// A rule references a field name the data source doesn't expose.
    /// Surfaced at load time so typo'd rules never reach evaluation.
    case unknownField(url: URL, source: RuleSource, field: String)

    /// Two or more rules share the same ID.
    case duplicateRuleID(id: String, urls: [URL])

    /// The directory passed to ``OWRules/loadRules(from:)`` doesn't
    /// exist or isn't readable.
    case rulesDirectoryUnreadable(url: URL, reason: String)
}

extension OWRulesError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .yamlParseFailed(let url, let reason):
            return "\(url.lastPathComponent): YAML parse failed — \(reason)"
        case .schemaViolation(let url, let field, let reason):
            return "\(url.lastPathComponent): invalid '\(field)' — \(reason)"
        case .unknownField(let url, let source, let field):
            return "\(url.lastPathComponent): unknown field '\(field)' for source '\(source.rawValue)'"
        case .duplicateRuleID(let id, let urls):
            let paths = urls.map { $0.lastPathComponent }.joined(separator: ", ")
            return "duplicate rule id '\(id)' in: \(paths)"
        case .rulesDirectoryUnreadable(let url, let reason):
            return "rules directory '\(url.path)' unreadable — \(reason)"
        }
    }
}
