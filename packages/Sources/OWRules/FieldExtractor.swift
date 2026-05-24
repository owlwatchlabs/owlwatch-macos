import Foundation
import OWNetwork
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
        case "scope": return .string(launchScopeSnakeCase(service.scope))
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

    // MARK: - Binary

    static let binaryFields: Set<String> = [
        "path", "is_universal", "slice_count", "architectures",
        "linked_dylibs", "rpaths", "has_rwx_segment", "max_section_entropy"
    ]

    static func extract(_ field: String, from summary: BinarySummary) -> FieldValue {
        switch field {
        case "path": return .string(summary.path)
        case "is_universal": return .boolean(summary.isUniversal)
        case "slice_count": return .integer(Int64(summary.sliceCount))
        case "architectures": return .stringArray(summary.architectures)
        case "linked_dylibs": return .stringArray(summary.linkedDylibs)
        case "rpaths": return .stringArray(summary.rpaths)
        case "has_rwx_segment": return .boolean(summary.hasRWXSegment)
        case "max_section_entropy": return .double(summary.maxSectionEntropy)
        default: return .missing
        }
    }

    // MARK: - Network connection

    static let networkFields: Set<String> = [
        "pid", "fd", "family", "protocol_name",
        "local_address", "local_port",
        "remote_address", "remote_port",
        "tcp_state", "is_listener"
    ]

    static func extract(_ field: String, from connection: Connection) -> FieldValue {
        switch field {
        case "pid": return .integer(Int64(connection.pid))
        case "fd": return .integer(Int64(connection.fd))
        case "family": return .string(connection.family.rawValue)
        case "protocol_name": return .string(connection.protocol.rawValue)
        case "local_address":
            return connection.localAddress.map(FieldValue.string) ?? .missing
        case "local_port":
            return connection.localPort.map { .integer(Int64($0)) } ?? .missing
        case "remote_address":
            return connection.remoteAddress.map(FieldValue.string) ?? .missing
        case "remote_port":
            return connection.remotePort.map { .integer(Int64($0)) } ?? .missing
        case "tcp_state":
            return connection.tcpState.map { .string($0.rawValue) } ?? .missing
        case "is_listener": return .boolean(connection.isListener)
        default: return .missing
        }
    }

    // MARK: - Kernel extension

    static let kernelExtensionFields: Set<String> = [
        "bundle_path", "bundle_identifier", "short_version",
        "bundle_version", "executable_name", "executable_path", "scope"
    ]

    static func extract(_ field: String, from kext: KernelExtension) -> FieldValue {
        switch field {
        case "bundle_path": return .string(kext.bundlePath)
        case "bundle_identifier":
            return kext.bundleIdentifier.map(FieldValue.string) ?? .missing
        case "short_version":
            return kext.shortVersion.map(FieldValue.string) ?? .missing
        case "bundle_version":
            return kext.bundleVersion.map(FieldValue.string) ?? .missing
        case "executable_name":
            return kext.executableName.map(FieldValue.string) ?? .missing
        case "executable_path":
            return kext.executablePath.map(FieldValue.string) ?? .missing
        case "scope": return .string(kext.scope.rawValue)
        default: return .missing
        }
    }

    // MARK: - Code signature

    static let signatureFields: Set<String> = [
        "path", "is_signed", "is_valid", "signature_type",
        "identifier", "team_identifier", "cd_hash",
        "authorities", "flags",
        "has_hardened_runtime", "hardened_runtime_version",
        "is_stapled_for_notarization", "entitlements_count"
    ]

    static func extract(_ field: String, from signature: SignatureSummary) -> FieldValue {
        switch field {
        case "path": return .string(signature.path)
        case "is_signed": return .boolean(signature.isSigned)
        case "is_valid": return .boolean(signature.isValid)
        case "signature_type": return .string(signature.signatureType)
        case "identifier":
            return signature.identifier.map(FieldValue.string) ?? .missing
        case "team_identifier":
            return signature.teamIdentifier.map(FieldValue.string) ?? .missing
        case "cd_hash":
            return signature.cdHashHex.map(FieldValue.string) ?? .missing
        case "authorities":
            return signature.authoritiesJoined.isEmpty ? .missing : .string(signature.authoritiesJoined)
        case "flags":
            return signature.flagsSymbolic.isEmpty ? .missing : .string(signature.flagsSymbolic)
        case "has_hardened_runtime": return .boolean(signature.hasHardenedRuntime)
        case "hardened_runtime_version":
            return signature.hardenedRuntimeVersion.map(FieldValue.string) ?? .missing
        case "is_stapled_for_notarization":
            return .boolean(signature.isStapledForNotarization)
        case "entitlements_count": return .integer(Int64(signature.entitlementsCount))
        default: return .missing
        }
    }

    // MARK: - Enum value mapping

    /// Map `LaunchScope` to the snake_case form rules use. The
    /// upstream enum's raw values are camelCase
    /// (`systemDaemon`, `userAgent`, ...) but the rule format
    /// uniformly uses snake_case (`system_daemon`, `user_agent`).
    /// Explicit table — auto-deriving would surface the camelCase
    /// form and clash with rule-author expectations.
    private static func launchScopeSnakeCase(_ scope: LaunchScope) -> String {
        switch scope {
        case .platformDaemon: return "platform_daemon"
        case .platformAgent: return "platform_agent"
        case .systemDaemon: return "system_daemon"
        case .systemAgent: return "system_agent"
        case .userAgent: return "user_agent"
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
        case .binary: return binaryFields
        case .network: return networkFields
        case .kernelExtension: return kernelExtensionFields
        case .signature: return signatureFields
        }
    }
}
