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

    public var displayName: String {
        switch self {
        case .process: return "Process"
        case .launchService: return "Launch Service"
        case .loginItem: return "Login Item"
        }
    }
}
