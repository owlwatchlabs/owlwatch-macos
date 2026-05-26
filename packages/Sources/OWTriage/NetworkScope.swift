import OWNetwork

/// Triage-oriented scope of a network endpoint, derived purely from
/// the `Connection`'s family + remoteAddress.
///
/// This is **derivation only** — no new signal. It maps `OWNetwork`'s
/// raw IP / unix-socket data into the four buckets the UI cares
/// about so the row can tint internet traffic distinctly from
/// loopback / LAN / IPC.
public enum NetworkScope: Equatable, Hashable, Sendable {
    /// Public-internet routable address — what the operator cares
    /// most about. The only scope the UI saturates.
    case internetPublic

    /// RFC 1918 / IPv6 unique-local / link-local. Reachable on the
    /// local network only.
    case lan

    /// `127.0.0.0/8` or `::1`. In-host traffic.
    case localhost

    /// Unix-domain socket — inter-process communication.
    case ipc

    /// Listener (no remote bound) or anything the parser couldn't
    /// classify. Distinguished from the populated cases so the
    /// caller can choose to surface "unknown" vs "—".
    case unknown

    /// Short label for the row.
    public var label: String {
        switch self {
        case .internetPublic: return "internet"
        case .lan:            return "LAN"
        case .localhost:      return "localhost"
        case .ipc:            return "IPC"
        case .unknown:        return "—"
        }
    }

    /// Build a scope from a connection. Listeners (`remoteAddress
    /// == nil`) collapse to `.unknown` since there's no remote to
    /// classify; the caller is expected to render listeners
    /// separately via `Connection.isListener`.
    public init(_ connection: Connection) {
        // Unix-domain → IPC. Family is the authoritative signal,
        // not the remote (Unix sockets may have an empty remote).
        if connection.family == .unix {
            self = .ipc
            return
        }
        guard let remote = connection.remoteAddress,
              let address = IPAddress(remote) else {
            self = .unknown
            return
        }
        if address.isLoopback {
            self = .localhost
        } else if address.isPrivate || address.isLinkLocal {
            // isPrivate covers RFC 1918 v4 + fc00::/7 v6 unique-local;
            // isLinkLocal covers 169.254/16 + fe80::/10.
            self = .lan
        } else {
            self = .internetPublic
        }
    }
}
