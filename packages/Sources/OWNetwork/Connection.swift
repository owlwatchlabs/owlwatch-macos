import Darwin
import Foundation

/// A point-in-time view of one network socket held by a running process.
///
/// One `Connection` per socket file descriptor. For a TCP listener that has
/// no active peer, ``remoteAddress`` and ``remotePort`` are `nil` and
/// ``tcpState`` is ``TCPState/listen``. For an established connection both
/// endpoints are populated. UDP sockets carry endpoints but no ``tcpState``.
///
/// The snapshot is captured by walking each visible process's file
/// descriptor table via `proc_pidinfo(PROC_PIDLISTFDS)` and calling
/// `proc_pidfdinfo(PROC_PIDFDSOCKETINFO)` on each socket fd — the same
/// data path `lsof -i` uses. Unprivileged callers see only their own
/// processes' sockets; root sees everything.
public struct Connection: Sendable, Equatable, Hashable {
    /// PID of the process holding the socket.
    public let pid: pid_t

    /// File descriptor number within that process.
    public let fd: Int32

    /// `.ipv4` / `.ipv6`. M4.1 covers IP sockets only; Unix-domain support
    /// lands in M4.2.
    public let family: AddressFamily

    /// `.tcp` / `.udp`.
    public let `protocol`: TransportProtocol

    /// Textual local address. IPv4 in dotted-quad (e.g. `"127.0.0.1"`),
    /// IPv6 in colon-separated form (e.g. `"::1"`, `"fe80::1"`). `"0.0.0.0"`
    /// / `"::"` are the wildcard binds, common on listeners.
    public let localAddress: String?

    /// Local port in host byte order. `nil` only when the socket has not
    /// been bound; populated for every listener and connected socket.
    public let localPort: UInt16?

    /// Textual remote address, when the socket is connected. `nil` for
    /// listeners and unbound sockets.
    public let remoteAddress: String?

    /// Remote port. `nil` when ``remoteAddress`` is.
    public let remotePort: UInt16?

    /// TCP connection state for `.tcp` sockets; `nil` for UDP.
    public let tcpState: TCPState?

    public init(
        pid: pid_t,
        fd: Int32,
        family: AddressFamily,
        protocol: TransportProtocol,
        localAddress: String?,
        localPort: UInt16?,
        remoteAddress: String?,
        remotePort: UInt16?,
        tcpState: TCPState?
    ) {
        self.pid = pid
        self.fd = fd
        self.family = family
        self.protocol = `protocol`
        self.localAddress = localAddress
        self.localPort = localPort
        self.remoteAddress = remoteAddress
        self.remotePort = remotePort
        self.tcpState = tcpState
    }

    /// `true` when this connection is listening for inbound traffic.
    ///
    /// - TCP: socket is in the `LISTEN` state.
    /// - UDP: socket is bound to a local address but has no active peer.
    /// - Unix (stream or datagram): socket has a bound filesystem path but
    ///   no connected peer. This matches the kernel's notion of a server
    ///   socket for both stream (XPC service host) and datagram families.
    public var isListener: Bool {
        switch `protocol` {
        case .tcp:
            return tcpState == .listen
        case .udp:
            return localPort != nil && remoteAddress == nil
        case .unixStream, .unixDatagram:
            return localAddress != nil && remoteAddress == nil
        }
    }
}

/// Address family the socket uses.
///
/// For ``unix`` sockets, ``Connection/localAddress`` carries the filesystem
/// path the socket was bound to (e.g. `/var/run/com.apple.foo.sock`), not
/// an IP. Anonymous Unix sockets (`socketpair(2)`-style) have `nil` for
/// both `localAddress` and `remoteAddress`.
public enum AddressFamily: String, Sendable, Equatable, Hashable, CaseIterable {
    case ipv4
    case ipv6
    case unix
}

/// Transport protocol / socket type carried over the socket.
///
/// IP sockets are ``tcp`` or ``udp``. Unix-domain sockets are
/// ``unixStream`` (`SOCK_STREAM`, used by XPC and most system services) or
/// ``unixDatagram`` (`SOCK_DGRAM`, rarer).
public enum TransportProtocol: String, Sendable, Equatable, Hashable, CaseIterable {
    case tcp
    case udp
    case unixStream = "unix-stream"
    case unixDatagram = "unix-dgram"
}

/// TCP connection state.
///
/// Mirrors the `TCPS_*` values from `<netinet/tcp_fsm.h>`. Owlwatch's
/// detection rules in M13 will branch on these — `LISTEN` flags a service
/// surface, `ESTABLISHED` flags an active connection, the WAIT states are
/// useful for tracking connections in teardown.
public enum TCPState: String, Sendable, Equatable, Hashable, CaseIterable {
    case closed
    case listen
    case synSent
    case synReceived
    case established
    case closeWait
    case finWait1
    case closing
    case lastAck
    case finWait2
    case timeWait

    /// Map from the kernel's `TCPS_*` integer to the Swift case. `nil` for
    /// any value the kernel reports that we don't recognize. Values are
    /// stable across macOS versions — pinned in tests.
    static func from(rawTcpState: Int32) -> TCPState? {
        kernelStateMap[rawTcpState]
    }

    private static let kernelStateMap: [Int32: TCPState] = [
        0: .closed,
        1: .listen,
        2: .synSent,
        3: .synReceived,
        4: .established,
        5: .closeWait,
        6: .finWait1,
        7: .closing,
        8: .lastAck,
        9: .finWait2,
        10: .timeWait
    ]

    /// Stable uppercase form for display (e.g. `"ESTABLISHED"`, `"LISTEN"`).
    public var displayName: String {
        switch self {
        case .closed: return "CLOSED"
        case .listen: return "LISTEN"
        case .synSent: return "SYN_SENT"
        case .synReceived: return "SYN_RCVD"
        case .established: return "ESTABLISHED"
        case .closeWait: return "CLOSE_WAIT"
        case .finWait1: return "FIN_WAIT_1"
        case .closing: return "CLOSING"
        case .lastAck: return "LAST_ACK"
        case .finWait2: return "FIN_WAIT_2"
        case .timeWait: return "TIME_WAIT"
        }
    }
}

/// Errors thrown by ``OWNetwork/OWNetwork``.
public enum OWNetworkError: Error, Sendable, Equatable {
    /// The process exists but we couldn't enumerate its file descriptors.
    /// Caller likely lacks permission (other-user process, kernel task).
    case unreachable(pid: pid_t, errno: Int32)
}
