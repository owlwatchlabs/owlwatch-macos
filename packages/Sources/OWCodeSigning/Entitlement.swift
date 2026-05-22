import Foundation

/// A single entitlement value, normalized from the property-list type system
/// the Security framework returns into a Swift `Sendable` enum.
///
/// Entitlements in practice are overwhelmingly booleans (e.g.
/// `com.apple.security.app-sandbox = true`), so ``boolValue`` and
/// ``stringValue`` cover the common path. The other cases exist because
/// some entitlements carry richer shape:
///
/// - `keychain-access-groups` is an array of strings.
/// - `com.apple.developer.icloud-services` is an array of strings.
/// - `com.apple.security.temporary-exception.files.absolute-path.read-only`
///   is an array of strings.
/// - Apple Pay and some media entitlements carry nested dictionaries.
///
/// Numeric and `Data` entitlements are rare but the cases exist for
/// completeness — a malformed or unusual signature shouldn't drop values
/// silently.
public enum Entitlement: Sendable, Equatable {
    case bool(Bool)
    case integer(Int64)
    case string(String)
    case data(Data)
    case array([Entitlement])
    case dictionary([String: Entitlement])

    /// Convenience: returns the wrapped `Bool` for ``bool`` cases.
    /// Most entitlements are booleans, so this avoids pattern-matching at
    /// every call site.
    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// Convenience: returns the wrapped `String` for ``string`` cases.
    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// Build an ``Entitlement`` from the bridged `Any` returned by
    /// `SecCodeCopySigningInformation` under the `entitlements-dict` key.
    ///
    /// `CFBoolean` and `NSNumber` both bridge to Swift `Bool` via `as?`,
    /// which would otherwise collapse integer entitlements into the
    /// `.bool` case. We use `CFGetTypeID` to keep them separate.
    static func from(_ value: Any) -> Entitlement? {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            return .integer(number.int64Value)
        }
        if let string = value as? String {
            return .string(string)
        }
        if let data = value as? Data {
            return .data(data)
        }
        if let array = value as? [Any] {
            return .array(array.compactMap { from($0) })
        }
        if let dictionary = value as? [String: Any] {
            var result: [String: Entitlement] = [:]
            for (key, nested) in dictionary {
                if let value = from(nested) {
                    result[key] = value
                }
            }
            return .dictionary(result)
        }
        return nil
    }
}
