import Darwin
import Foundation
import Network
import NetworkExtension
import OWNetworkExt
import os

/// Helpers that turn an `NEFilterSocketFlow` into the `FlowEvent`
/// wire model. Lives in the extension target rather than
/// `OWNetworkExt` because all of it depends on `NetworkExtension`
/// — and pulling that framework into the shared module would link
/// it into the container app too, which we don't want.
///
/// Per the M7.2 brief: extract pid + path via audit token, use the
/// modern `remoteFlowEndpoint` / `localFlowEndpoint` (the
/// `*Endpoint` variants are deprecated), and never fabricate a
/// hostname when the kernel filter didn't surface one.
enum FlowExtraction {
    private static let log = Logger(
        subsystem: "com.owlwatchlabs.owlwatch.contentfilter",
        category: "flow-extraction"
    )

    /// Build a `FlowEvent` from the kernel flow object. Returns
    /// `nil` for flows that aren't socket flows (e.g. a future
    /// browser-flow case we don't model). On a sysext under
    /// `filter-data`, the cast effectively always succeeds.
    static func event(from flow: NEFilterFlow) -> FlowEvent? {
        guard let socketFlow = flow as? NEFilterSocketFlow else { return nil }
        let (pid, path) = identity(for: socketFlow)
        let (local, remote) = endpoints(for: socketFlow)
        return FlowEvent(
            id: socketFlow.identifier,
            timestamp: Date(),
            direction: direction(from: socketFlow.direction),
            family: family(from: socketFlow.socketFamily),
            protocol: protocolFamily(from: socketFlow.socketProtocol),
            localEndpoint: local,
            remoteEndpoint: remote,
            remoteHostname: socketFlow.remoteHostname,
            pid: pid,
            processPath: path
        )
    }

    /// Endpoint extraction. Uses the macOS 15+
    /// `localFlowEndpoint` / `remoteFlowEndpoint` accessors that
    /// return modern `Network.NWEndpoint` values. The legacy
    /// `localEndpoint` / `remoteEndpoint` properties were
    /// obsoleted out of the Xcode 26 / macOS 26 SDK, so the
    /// deployment target was bumped to 15 in concert.
    private static func endpoints(
        for flow: NEFilterSocketFlow
    ) -> (FlowEvent.Endpoint?, FlowEvent.Endpoint?) {
        return (modernEndpoint(flow.localFlowEndpoint),
                modernEndpoint(flow.remoteFlowEndpoint))
    }

    // MARK: - Identity

    /// pid + executable path for the owning process. Prefers
    /// `sourceAppAuditToken` (Apple's recommended "owning app"
    /// token) and falls back to `sourceProcessAuditToken` (added
    /// later for cases where they differ — e.g. helpers vs. their
    /// host app).
    private static func identity(for flow: NEFilterSocketFlow) -> (pid_t, String?) {
        let token = flow.sourceAppAuditToken ?? flow.sourceProcessAuditToken
        guard var auditToken = token.flatMap(decode) else {
            return (0, nil)
        }
        let pid = audit_token_to_pid(auditToken)
        let path = pathFromAuditToken(&auditToken)
        return (pid, path)
    }

    /// Decode the `Data` blob the framework hands us into an
    /// `audit_token_t`. macOS guarantees the layout is 8 32-bit
    /// integers (32 bytes); anything else is malformed and we
    /// bail.
    private static func decode(_ data: Data) -> audit_token_t? {
        guard data.count == MemoryLayout<audit_token_t>.size else { return nil }
        var token = audit_token_t()
        _ = withUnsafeMutableBytes(of: &token) { dest in
            data.copyBytes(to: dest.bindMemory(to: UInt8.self))
        }
        return token
    }

    /// `proc_pidpath_audittoken` (macOS 11+) is the race-free way
    /// to ask the kernel for a path given an audit token — it
    /// won't return the path of a process that re-execed under a
    /// reused pid since we asked.
    ///
    /// `PROC_PIDPATHINFO_MAXSIZE` (`<sys/proc_info.h>`) expands to
    /// `4 * MAXPATHLEN`; Swift's C macro importer can't evaluate
    /// that arithmetic, so we inline the value (4096) the same
    /// way OWProcess does.
    private static func pathFromAuditToken(_ token: inout audit_token_t) -> String? {
        let bufferSize = 4096
        var buffer = [CChar](repeating: 0, count: bufferSize)
        let written = buffer.withUnsafeMutableBufferPointer { buf -> Int32 in
            proc_pidpath_audittoken(&token, buf.baseAddress, UInt32(bufferSize))
        }
        guard written > 0 else { return nil }
        return String(cString: buffer)
    }

    // MARK: - Field mapping

    private static func direction(from netDirection: NETrafficDirection) -> FlowEvent.Direction {
        switch netDirection {
        case .inbound:  return .inbound
        case .outbound: return .outbound
        case .any:      return .any
        @unknown default: return .any
        }
    }

    private static func family(from raw: Int32) -> FlowEvent.SocketFamily {
        switch raw {
        case AF_INET:  return .ipv4
        case AF_INET6: return .ipv6
        case AF_UNIX:  return .unix
        default:       return .unknown
        }
    }

    private static func protocolFamily(from raw: Int32) -> FlowEvent.SocketProtocol {
        switch raw {
        case IPPROTO_TCP:    return .tcp
        case IPPROTO_UDP:    return .udp
        // Unix-domain "socketProtocol" is 0 — the protocol slot
        // isn't meaningful for AF_UNIX. We tag it from the family
        // pass when the caller wants a single discriminator.
        case 0:              return .unix
        default:             return .unknown
        }
    }

    private static func modernEndpoint(_ endpoint: Network.NWEndpoint?) -> FlowEvent.Endpoint? {
        guard let endpoint else { return nil }
        switch endpoint {
        case .hostPort(let host, let port):
            return .ip(address: modernHostString(host), port: port.rawValue)
        case .unix(let path):
            return .unix(path: path)
        case .service, .url, .opaque:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    private static func modernHostString(_ host: Network.NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let address):     return "\(address)"
        case .ipv6(let address):     return "\(address)"
        case .name(let name, _):     return name
        @unknown default:            return "—"
        }
    }

}
