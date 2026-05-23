import Foundation

/// A polymorphic field value extracted from a data source item.
///
/// The rule format is declarative and string-flavored: a YAML
/// `starts_with:` predicate against a `pid:` field needs to compare a
/// *string* form of the PID. ``FieldValue`` normalizes the few
/// concrete shapes (string, bool, integer, missing) the data sources
/// produce into one comparable surface.
///
/// `nil` fields collapse to ``FieldValue/missing``; the predicate
/// evaluator distinguishes "field is missing" from "field is the
/// empty string" via ``isPresent``.
public enum FieldValue: Sendable, Equatable {
    case string(String)
    case integer(Int64)
    case boolean(Bool)
    /// Collection of strings — for fields like `arguments`. Predicates
    /// over collections match if any element satisfies the predicate.
    /// `exists` over a collection requires non-empty.
    case stringArray([String])
    case missing

    /// String form for string-flavored predicates (`equals`,
    /// `startsWith`, `contains`, ...). `Int64` formats as its decimal
    /// form; `Bool` formats as `"true"` / `"false"`. Missing returns
    /// `nil`.
    var asString: String? {
        switch self {
        case .string(let str): return str
        case .integer(let int): return String(int)
        case .boolean(let bool): return bool ? "true" : "false"
        case .stringArray(let array):
            // Collections concatenate via space — useful for argv-style
            // fields where authors want `contains: "--no-verify"` to
            // match across argument boundaries.
            return array.joined(separator: " ")
        case .missing: return nil
        }
    }

    var asBool: Bool? {
        if case .boolean(let bool) = self { return bool }
        return nil
    }

    /// `true` for any populated value; `false` for `.missing` and for
    /// `.stringArray([])`.
    var isPresent: Bool {
        switch self {
        case .missing: return false
        case .stringArray(let array): return !array.isEmpty
        default: return true
        }
    }
}
