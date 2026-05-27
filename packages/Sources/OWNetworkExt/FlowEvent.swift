import Foundation

/// One observation of a single socket flow seen by the M7
/// Content Filter system extension.
///
/// A `FlowEvent` is the wire format the extension pushes to the
/// container app over XPC. The fields are intentionally lean — no
/// payload, no TLS / DNS guessing, only what `NEFilterSocketFlow`
/// actually exposes. `remoteHostname` is the SNI / DNS-cached name
/// the kernel filter offers when it has one; it's frequently `nil`
/// (by-IP connections, ECH-encrypted SNI), and the consumer must
/// never fabricate a value.
///
/// Per M7 brief §7 guardrails: this is observation-only. The
/// provider always returns `.allow()`; no event implies a verdict
/// was applied.
public struct FlowEvent: Codable, Sendable, Equatable, Hashable {
    /// Stable identifier copied from `NEFilterFlow.identifier`. Lets
    /// the app de-duplicate across reconnects / heartbeat retries.
    public let id: UUID

    /// When the extension built the event (not when the socket
    /// opened — those are close enough for triage but distinct in
    /// principle).
    public let timestamp: Date

    public let direction: Direction
    public let family: SocketFamily
    public let `protocol`: SocketProtocol

    /// Local endpoint. `nil` only when the kernel didn't surface a
    /// bind / connect address yet (rare).
    public let localEndpoint: Endpoint?

    /// Remote endpoint. `nil` for unbound listeners and for Unix-
    /// domain sockets that don't carry one.
    public let remoteEndpoint: Endpoint?

    /// SNI / DNS-cached hostname from `NEFilterSocketFlow
    /// .remoteHostname`. Treat as best-effort — frequently `nil`.
    public let remoteHostname: String?

    /// pid of the process that owns the socket, derived from
    /// `sourceAppAuditToken` via `audit_token_to_pid`.
    public let pid: pid_t

    /// Absolute executable path resolved via
    /// `proc_pidpath_audittoken` — race-free vs. a pid round-trip
    /// on macOS 11+.
    public let processPath: String?

    public init(
        id: UUID,
        timestamp: Date,
        direction: Direction,
        family: SocketFamily,
        protocol: SocketProtocol,
        localEndpoint: Endpoint?,
        remoteEndpoint: Endpoint?,
        remoteHostname: String?,
        pid: pid_t,
        processPath: String?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.direction = direction
        self.family = family
        self.protocol = `protocol`
        self.localEndpoint = localEndpoint
        self.remoteEndpoint = remoteEndpoint
        self.remoteHostname = remoteHostname
        self.pid = pid
        self.processPath = processPath
    }

    public enum Direction: String, Codable, Sendable, Equatable, Hashable {
        case inbound
        case outbound
        case any
    }

    public enum SocketFamily: String, Codable, Sendable, Equatable, Hashable {
        case ipv4
        case ipv6
        case unix
        case unknown
    }

    public enum SocketProtocol: String, Codable, Sendable, Equatable, Hashable {
        case tcp
        case udp
        case unix
        case unknown
    }

    /// Endpoint shape. IP sockets carry `address`+`port`; Unix
    /// sockets carry the bound filesystem path. `Endpoint.unknown`
    /// stands in for anything the parser couldn't classify (so
    /// the consumer doesn't have to handle `nil` vs. unparseable
    /// separately).
    public enum Endpoint: Codable, Sendable, Equatable, Hashable {
        case ip(address: String, port: UInt16)
        case unix(path: String)
        case unknown

        /// Render for a single-line UI cell. IPv6 addresses get
        /// bracketed so `:port` reads as a separator, not as part
        /// of the address.
        public var displayString: String {
            switch self {
            case .ip(let address, let port):
                if address.contains(":") { return "[\(address)]:\(port)" }
                return "\(address):\(port)"
            case .unix(let path): return path
            case .unknown: return "—"
            }
        }
    }
}
