import Foundation

/// One predicate over a single field of a data source item. The
/// rule's `when.match` block carries a `[FieldName: Predicate]`
/// dictionary; the evaluator ANDs them together.
///
/// String predicates (`equals`, `startsWith`, `contains`, ...) are
/// case-sensitive — fields containing user-controlled text (paths,
/// argument vectors) preserve case and rule authors should not be
/// forced into ambiguous matching. Authors who need case-insensitive
/// matching reach for `.matches` with a `(?i)` regex prefix.
///
/// The `.exists` variant distinguishes `nil` from "field exists but
/// has the empty value". A `path:` set to an empty string is
/// **present**; a `path:` not in the snapshot at all is **missing**.
public indirect enum Predicate: Sendable, Equatable {
    /// Exact equality after coercing the field's value to `String`.
    case equals(String)

    /// Negated exact equality. `nil` fields do not match.
    case notEquals(String)

    /// String prefix match.
    case startsWith(String)

    /// String suffix match.
    case endsWith(String)

    /// String substring match.
    case contains(String)

    /// `NSRegularExpression`-compatible regex over the field's string
    /// form. Anchors (`^`, `$`) match the field's start and end.
    case matches(String)

    /// Set membership. Matches if the field's string form is in the
    /// set. Useful for short enumerations like
    /// `in: [bash, sh, zsh, ksh]`.
    case inSet(Set<String>)

    /// `true` matches when the field is present (non-nil); `false`
    /// matches when the field is nil. For collection fields, `true`
    /// requires non-empty.
    case exists(Bool)

    /// `true` matches when the field is the boolean `true`; `false`
    /// matches the boolean `false`. Errors at evaluation time if the
    /// field is not a boolean.
    case isBoolean(Bool)

    /// Strict numeric `>` comparison. Field value must be `.integer`
    /// or `.double`; non-numeric values never match. Added in M13.2
    /// for entropy thresholds and similar numeric tests.
    case greaterThan(Double)

    /// Strict numeric `<` comparison. Same constraints as `.greaterThan`.
    case lessThan(Double)
}

extension Predicate {
    /// Apply this predicate to a field value extracted from a data
    /// source item. Returns `true` if the predicate matches.
    ///
    /// The `FieldValue` abstraction is intentionally narrow — strings,
    /// booleans, integers, optional and collection variants. Adding a
    /// new variant requires extending the evaluator's matching logic
    /// here.
    func evaluate(against value: FieldValue) -> Bool {
        switch self {
        case .equals(let target):
            return value.asString == target
        case .notEquals(let target):
            guard let str = value.asString else { return false }
            return str != target
        case .startsWith(let prefix):
            return value.asString?.hasPrefix(prefix) ?? false
        case .endsWith(let suffix):
            return value.asString?.hasSuffix(suffix) ?? false
        case .contains(let needle):
            return value.asString?.contains(needle) ?? false
        case .matches(let pattern):
            guard let str = value.asString else { return false }
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return false
            }
            let range = NSRange(str.startIndex..<str.endIndex, in: str)
            return regex.firstMatch(in: str, options: [], range: range) != nil
        case .inSet(let set):
            guard let str = value.asString else { return false }
            return set.contains(str)
        case .exists(let expected):
            return value.isPresent == expected
        case .isBoolean(let expected):
            guard let bool = value.asBool else { return false }
            return bool == expected
        case .greaterThan(let threshold):
            guard let number = value.asDouble else { return false }
            return number > threshold
        case .lessThan(let threshold):
            guard let number = value.asDouble else { return false }
            return number < threshold
        }
    }
}
