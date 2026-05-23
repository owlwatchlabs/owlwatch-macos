import Foundation
import OWPersistence
import OWProcess

/// Maps a rule's field name (the YAML key) to a ``FieldValue`` for a
/// concrete data source item.
///
/// Each ``RuleSource`` declares its field vocabulary here. Adding a
/// new field is a one-line change in the relevant `extract` function;
/// adding a new source means extending ``RuleSource`` and writing a
/// new `extract` overload.
///
/// Field names are `snake_case` to match the YAML convention even
/// when the underlying Swift property is camelCase. The translation
/// is explicit (not algorithmic) so rule authors get a clear list of
/// queryable fields rather than guessing at name mangling.
enum FieldExtractor {
    // MARK: - Process

    /// Field vocabulary for the `process` source.
    static let processFields: Set<String> = [
        "pid", "parent_pid", "name", "path", "user_id", "arguments"
    ]

    static func extract(_ field: String, from process: RunningProcess) -> FieldValue {
        switch field {
        case "pid": return .integer(Int64(process.pid))
        case "parent_pid": return .integer(Int64(process.parentPid))
        case "name": return .string(process.name)
        case "path": return process.path.map(FieldValue.string) ?? .missing
        case "user_id": return .integer(Int64(process.userId))
        case "arguments":
            guard let args = process.arguments else { return .missing }
            return .stringArray(args)
        default: return .missing
        }
    }

    // MARK: - Launch service

    static let launchServiceFields: Set<String> = [
        "plist_path", "scope", "label", "executable_path",
        "arguments", "run_at_load", "runs_as_root", "is_disabled"
    ]

    static func extract(_ field: String, from service: LaunchService) -> FieldValue {
        switch field {
        case "plist_path": return .string(service.plistPath)
        case "scope": return .string(service.scope.rawValue)
        case "label": return service.label.map(FieldValue.string) ?? .missing
        case "executable_path":
            return service.executablePath.map(FieldValue.string) ?? .missing
        case "arguments": return .stringArray(service.arguments)
        case "run_at_load": return .boolean(service.runAtLoad)
        case "runs_as_root": return .boolean(service.scope.runsAsRoot)
        case "is_disabled": return .boolean(service.isDisabled)
        default: return .missing
        }
    }

    // MARK: - Login item

    static let loginItemFields: Set<String> = [
        "identifier", "developer_name", "team_identifier",
        "bundle_identifier", "parent_identifier", "url", "is_enabled"
    ]

    static func extract(_ field: String, from item: LoginItem) -> FieldValue {
        switch field {
        case "identifier": return item.identifier.map(FieldValue.string) ?? .missing
        case "developer_name":
            return item.developerName.map(FieldValue.string) ?? .missing
        case "team_identifier":
            return item.teamIdentifier.map(FieldValue.string) ?? .missing
        case "bundle_identifier":
            return item.bundleIdentifier.map(FieldValue.string) ?? .missing
        case "parent_identifier":
            return item.parentIdentifier.map(FieldValue.string) ?? .missing
        case "url": return item.url.map(FieldValue.string) ?? .missing
        case "is_enabled": return .boolean(item.isEnabled)
        default: return .missing
        }
    }

    // MARK: - Field validation

    /// Field names a rule may reference for the given source.
    /// Used at load time to reject rules with typo'd field names.
    static func fields(for source: RuleSource) -> Set<String> {
        switch source {
        case .process: return processFields
        case .launchService: return launchServiceFields
        case .loginItem: return loginItemFields
        }
    }
}
