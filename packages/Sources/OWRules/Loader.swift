import Foundation
import Yams

/// Loads `Rule` instances from YAML documents.
///
/// The loader is strict: every field is type-checked, unknown
/// predicate forms are rejected, unknown field names are rejected
/// against the source's field vocabulary. The intent is that a
/// well-formed YAML file produces a usable `Rule` and a malformed
/// one produces a precise error message — never a silent no-op rule.
enum RuleLoader {
    /// Parse a single rule from a YAML file at `url`.
    static func loadRule(from url: URL) throws -> Rule {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw OWRulesError.yamlParseFailed(url: url, reason: error.localizedDescription)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw OWRulesError.yamlParseFailed(url: url, reason: "file is not valid UTF-8")
        }
        let raw: Any?
        do {
            raw = try Yams.load(yaml: text)
        } catch {
            throw OWRulesError.yamlParseFailed(url: url, reason: "\(error)")
        }
        guard let dict = raw as? [String: Any] else {
            throw OWRulesError.schemaViolation(
                url: url, field: "(root)",
                reason: "document root must be a mapping"
            )
        }
        return try decodeRule(dict, url: url)
    }

    /// Parse every `.yml` / `.yaml` file in `directory` and return
    /// the rules sorted by ID. Duplicate IDs across files raise
    /// `OWRulesError.duplicateRuleID`.
    static func loadRules(from directory: URL) throws -> [Rule] {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
            throw OWRulesError.rulesDirectoryUnreadable(
                url: directory,
                reason: "not a directory"
            )
        }
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
        } catch {
            throw OWRulesError.rulesDirectoryUnreadable(
                url: directory,
                reason: error.localizedDescription
            )
        }
        let yamlFiles = contents
            .filter { $0.pathExtension == "yml" || $0.pathExtension == "yaml" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var loaded: [String: (Rule, URL)] = [:]
        var ordered: [Rule] = []
        for file in yamlFiles {
            let rule = try loadRule(from: file)
            if let existing = loaded[rule.id] {
                throw OWRulesError.duplicateRuleID(id: rule.id, urls: [existing.1, file])
            }
            loaded[rule.id] = (rule, file)
            ordered.append(rule)
        }
        return ordered
    }

    // MARK: - Decoding

    private static func decodeRule(_ dict: [String: Any], url: URL) throws -> Rule {
        let id = try requireString(dict, field: "id", url: url)
        let name = try requireString(dict, field: "name", url: url)
        let description = dict["description"] as? String
        let mitre = dict["mitre"] as? String

        let severity: Severity
        if let raw = dict["severity"] as? String {
            guard let parsed = Severity(rawValue: raw) else {
                throw OWRulesError.schemaViolation(
                    url: url, field: "severity",
                    reason: "must be one of: \(Severity.allCases.map { $0.rawValue }.joined(separator: ", "))"
                )
            }
            severity = parsed
        } else {
            throw OWRulesError.schemaViolation(
                url: url, field: "severity",
                reason: "missing required field"
            )
        }

        guard let whenBlock = dict["when"] as? [String: Any] else {
            throw OWRulesError.schemaViolation(
                url: url, field: "when",
                reason: "missing required block"
            )
        }
        let sourceRaw = try requireString(whenBlock, field: "when.source", url: url)
        guard let source = RuleSource(rawValue: sourceRaw) else {
            throw OWRulesError.schemaViolation(
                url: url, field: "when.source",
                reason: "unknown source '\(sourceRaw)' — must be one of: "
                    + RuleSource.allCases.map { $0.rawValue }.joined(separator: ", ")
            )
        }

        var matchDict: [String: Predicate] = [:]
        if let rawMatch = whenBlock["match"] as? [String: Any] {
            let allowedFields = FieldExtractor.fields(for: source)
            for (field, rawPredicate) in rawMatch {
                guard allowedFields.contains(field) else {
                    throw OWRulesError.unknownField(url: url, source: source, field: field)
                }
                matchDict[field] = try decodePredicate(rawPredicate, field: field, url: url)
            }
        }

        let evidence = (dict["evidence"] as? [String]) ?? []
        // Evidence fields must also be valid field names for the source.
        let allowedFields = FieldExtractor.fields(for: source)
        for field in evidence where !allowedFields.contains(field) {
            throw OWRulesError.unknownField(url: url, source: source, field: field)
        }

        return Rule(
            id: id,
            name: name,
            description: description,
            mitre: mitre,
            severity: severity,
            source: source,
            match: matchDict,
            evidence: evidence,
            sourceURL: url
        )
    }

    private static func decodePredicate(_ raw: Any, field: String, url: URL) throws -> Predicate {
        // A scalar string is shorthand for `equals: <string>`.
        if let scalar = raw as? String {
            return .equals(scalar)
        }
        guard let dict = raw as? [String: Any] else {
            throw OWRulesError.schemaViolation(
                url: url, field: "when.match.\(field)",
                reason: "must be a scalar or a mapping"
            )
        }
        guard dict.count == 1, let (key, value) = dict.first else {
            throw OWRulesError.schemaViolation(
                url: url, field: "when.match.\(field)",
                reason: "predicate mapping must have exactly one key"
            )
        }
        if let stringPred = try decodeStringPredicate(key: key, value: value, field: field, url: url) {
            return stringPred
        }
        if let booleanPred = try decodeBooleanPredicate(key: key, value: value, field: field, url: url) {
            return booleanPred
        }
        if let numericPred = try decodeNumericPredicate(key: key, value: value, field: field, url: url) {
            return numericPred
        }
        if key == "in" {
            return try decodeInPredicate(value: value, field: field, url: url)
        }
        throw OWRulesError.schemaViolation(
            url: url, field: "when.match.\(field)",
            reason: "unknown predicate '\(key)'"
        )
    }

    private static func requireString(_ dict: [String: Any], field: String, url: URL) throws -> String {
        guard let value = dict[field.split(separator: ".").last.map(String.init) ?? field] as? String else {
            throw OWRulesError.schemaViolation(
                url: url, field: field,
                reason: "missing required string field"
            )
        }
        return value
    }

    // MARK: - Predicate decode helpers

    /// String-shaped predicates (`equals`, `not_equals`, `starts_with`,
    /// `ends_with`, `contains`, `matches`). Returns nil when `key`
    /// doesn't match any of them.
    private static func decodeStringPredicate(
        key: String, value: Any, field: String, url: URL
    ) throws -> Predicate? {
        switch key {
        case "equals":
            return .equals(try requireScalar(value, key: key, field: field, url: url))
        case "not_equals":
            return .notEquals(try requireScalar(value, key: key, field: field, url: url))
        case "starts_with":
            return .startsWith(try requireScalar(value, key: key, field: field, url: url))
        case "ends_with":
            return .endsWith(try requireScalar(value, key: key, field: field, url: url))
        case "contains":
            return .contains(try requireScalar(value, key: key, field: field, url: url))
        case "matches":
            let pattern = try requireScalar(value, key: key, field: field, url: url)
            guard (try? NSRegularExpression(pattern: pattern)) != nil else {
                throw OWRulesError.schemaViolation(
                    url: url, field: "when.match.\(field).matches",
                    reason: "invalid regular expression: \(pattern)"
                )
            }
            return .matches(pattern)
        default:
            return nil
        }
    }

    /// Boolean-shaped predicates (`exists`, `is_true`, `is_false`).
    private static func decodeBooleanPredicate(
        key: String, value: Any, field: String, url: URL
    ) throws -> Predicate? {
        switch key {
        case "exists":
            guard let bool = value as? Bool else {
                throw OWRulesError.schemaViolation(
                    url: url, field: "when.match.\(field).exists",
                    reason: "must be a boolean"
                )
            }
            return .exists(bool)
        case "is_true":
            guard let bool = value as? Bool, bool else {
                throw OWRulesError.schemaViolation(
                    url: url, field: "when.match.\(field).is_true",
                    reason: "must be the boolean true"
                )
            }
            return .isBoolean(true)
        case "is_false":
            guard let bool = value as? Bool, bool else {
                throw OWRulesError.schemaViolation(
                    url: url, field: "when.match.\(field).is_false",
                    reason: "must be the boolean true"
                )
            }
            return .isBoolean(false)
        default:
            return nil
        }
    }

    /// Numeric predicates (`greater_than`, `less_than`).
    private static func decodeNumericPredicate(
        key: String, value: Any, field: String, url: URL
    ) throws -> Predicate? {
        switch key {
        case "greater_than":
            return .greaterThan(try requireDouble(value, key: key, field: field, url: url))
        case "less_than":
            return .lessThan(try requireDouble(value, key: key, field: field, url: url))
        default:
            return nil
        }
    }

    /// Set-membership predicate (`in`).
    private static func decodeInPredicate(value: Any, field: String, url: URL) throws -> Predicate {
        guard let array = value as? [Any] else {
            throw OWRulesError.schemaViolation(
                url: url, field: "when.match.\(field).in",
                reason: "must be a sequence of scalars"
            )
        }
        let strings = array.compactMap { $0 as? String }
        guard strings.count == array.count else {
            throw OWRulesError.schemaViolation(
                url: url, field: "when.match.\(field).in",
                reason: "sequence must contain only strings"
            )
        }
        return .inSet(Set(strings))
    }

    private static func requireDouble(_ raw: Any, key: String, field: String, url: URL) throws -> Double {
        if let double = raw as? Double { return double }
        if let int = raw as? Int { return Double(int) }
        throw OWRulesError.schemaViolation(
            url: url, field: "when.match.\(field).\(key)",
            reason: "must be a number"
        )
    }

    private static func requireScalar(_ raw: Any, key: String, field: String, url: URL) throws -> String {
        // Yams gives us String for scalars; integers and booleans
        // arrive as their bridged types. Coerce explicitly so rule
        // authors can write `starts_with: 1000` and get string
        // semantics.
        if let str = raw as? String { return str }
        if let int = raw as? Int { return String(int) }
        if let bool = raw as? Bool { return bool ? "true" : "false" }
        throw OWRulesError.schemaViolation(
            url: url, field: "when.match.\(field).\(key)",
            reason: "must be a scalar"
        )
    }
}
