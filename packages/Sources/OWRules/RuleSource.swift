import Foundation

/// A data source a rule iterates over. Each source corresponds to one
/// `OW*` snapshot reader and a fixed vocabulary of fields the rule's
/// `when.match` block may reference.
///
/// M13.1 ships three sources. Network / binary / signature / log
/// sources follow in M13.2–M13.4 by extending this enum and the
/// matching field tables in ``FieldExtractor``.
public enum RuleSource: String, Sendable, Codable, CaseIterable, Hashable {
    /// Iterates `OWProcess.all(...)`. Fields: `pid`, `parent_pid`,
    /// `name`, `path`, `user_id`, `arguments`.
    case process

    /// Iterates `OWPersistence.launchServices()`. Fields: `plist_path`,
    /// `scope`, `label`, `executable_path`, `arguments`, `run_at_load`,
    /// `runs_as_root`, `is_disabled`.
    case launchService = "launch_service"

    /// Iterates `OWPersistence.loginItems()`. Fields: `identifier`,
    /// `developer_name`, `team_identifier`, `bundle_identifier`,
    /// `parent_identifier`, `url`, `is_enabled`.
    case loginItem = "login_item"

    /// Iterates `BinarySummary`s parsed from every unique executable
    /// in the process snapshot. Fields: `path`, `is_universal`,
    /// `architectures`, `linked_dylibs`, `rpaths`, `has_rwx_segment`,
    /// `max_section_entropy`, `slice_count`. Added in M13.2.
    case binary

    /// Iterates `OWNetwork.snapshot()`. Fields: `pid`, `fd`, `family`,
    /// `protocol_name`, `local_address`, `local_port`, `remote_address`,
    /// `remote_port`, `tcp_state`, `is_listener`. Added in M13.3.
    case network

    /// Iterates `OWPersistence.kernelExtensions()`. Fields:
    /// `bundle_path`, `bundle_identifier`, `short_version`,
    /// `bundle_version`, `executable_name`, `executable_path`, `scope`.
    /// Added in M13.3.
    case kernelExtension = "kernel_extension"

    /// Iterates `SignatureSummary`s captured via
    /// `OWCodeSigning.inspect(at:)` for every unique executable path
    /// in the process snapshot. Fields: `path`, `is_signed`,
    /// `is_valid`, `signature_type`, `identifier`, `team_identifier`,
    /// `cd_hash`, `authorities`, `flags`, `has_hardened_runtime`,
    /// `hardened_runtime_version`, `is_stapled_for_notarization`,
    /// `entitlements_count`. Added in M13.4.
    case signature

    public var displayName: String {
        switch self {
        case .process: return "Process"
        case .launchService: return "Launch Service"
        case .loginItem: return "Login Item"
        case .binary: return "Binary"
        case .network: return "Network"
        case .kernelExtension: return "Kernel Extension"
        case .signature: return "Signature"
        }
    }
}
