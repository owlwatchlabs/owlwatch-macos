import Darwin
import Foundation

/// Host network state — open IP sockets attributed to the process that
/// holds them.
///
/// `OWNetwork` is the M4 companion to ``OWProcess``: where `OWProcess`
/// answers "what processes are running?", `OWNetwork` answers "what is
/// each of those processes connected to?". Same data path as `lsof -i`
/// and the same posture as M1 — `proc_pidinfo(PROC_PIDLISTFDS)` per
/// process, then `proc_pidfdinfo(PROC_PIDFDSOCKETINFO)` per socket fd.
///
/// Unprivileged callers see only their own processes' sockets. Root sees
/// everything. M4.1 covers TCP and UDP over IPv4 / IPv6; Unix-domain
/// sockets land in M4.2.
///
/// This is a snapshot library, not a stream. For real-time visibility of
/// new connections, the M7 Network Extension filter is the right tool.
/// `OWNetwork` answers point-in-time questions: "is this process
/// connected to anything right now?", "who's listening on port 5432?",
/// "which processes have open TCP connections to 1.2.3.4?".
public enum OWNetwork {
    /// Capture a snapshot of every IP socket held by every visible
    /// process.
    ///
    /// Processes the caller can't introspect (typically other users'
    /// processes when running unprivileged) are silently skipped — the
    /// `proc_pidinfo(PROC_PIDLISTFDS)` call returns 0 / EPERM and we move
    /// on. This matches `lsof -i`'s behavior of partial visibility.
    public static func snapshot() throws -> [Connection] {
        let pids = listPIDs()
        var connections: [Connection] = []
        for pid in pids where pid > 0 {
            connections.append(contentsOf: connectionsForProcess(pid))
        }
        return connections
    }

    /// Capture a snapshot of every IP socket held by one specific
    /// process.
    ///
    /// - Throws: ``OWNetworkError/unreachable(pid:errno:)`` when the
    ///   process exists but the caller lacks permission to enumerate
    ///   its descriptors.
    public static func snapshot(pid: pid_t) throws -> [Connection] {
        // Distinguish "no sockets" from "couldn't access" by trying the
        // first PROC_PIDLISTFDS call directly.
        let listSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard listSize >= 0 else {
            throw OWNetworkError.unreachable(pid: pid, errno: errno)
        }
        return connectionsForProcess(pid)
    }
}

private func listPIDs() -> [pid_t] {
    let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
    guard byteCount > 0 else { return [] }
    let pidCount = Int(byteCount) / MemoryLayout<pid_t>.stride
    var pids = [pid_t](repeating: 0, count: pidCount)
    let actual = pids.withUnsafeMutableBufferPointer { buf in
        proc_listpids(UInt32(PROC_ALL_PIDS), 0, buf.baseAddress, Int32(buf.count * MemoryLayout<pid_t>.stride))
    }
    guard actual > 0 else { return [] }
    let actualCount = Int(actual) / MemoryLayout<pid_t>.stride
    return Array(pids.prefix(actualCount))
}

private func connectionsForProcess(_ pid: pid_t) -> [Connection] {
    let stride = MemoryLayout<proc_fdinfo>.stride
    let listSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
    guard listSize > 0 else { return [] }

    let fdCount = Int(listSize) / stride
    var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: fdCount)
    let actualSize = fds.withUnsafeMutableBufferPointer { buf in
        proc_pidinfo(pid, PROC_PIDLISTFDS, 0, buf.baseAddress, Int32(buf.count * stride))
    }
    guard actualSize > 0 else { return [] }

    let socketFdType: Int32 = 2  // PROX_FDTYPE_SOCKET from <sys/proc_info.h>
    let actualCount = Int(actualSize) / stride
    var connections: [Connection] = []
    for entry in fds.prefix(actualCount) {
        let fdtype = Int32(bitPattern: entry.proc_fdtype)
        guard fdtype == socketFdType else { continue }
        if let connection = connectionFor(pid: pid, fd: entry.proc_fd) {
            connections.append(connection)
        }
    }
    return connections
}

private func connectionFor(pid: pid_t, fd: Int32) -> Connection? {
    var info = socket_fdinfo()
    let size = withUnsafeMutablePointer(to: &info) { ptr in
        proc_pidfdinfo(pid, fd, PROC_PIDFDSOCKETINFO, ptr, Int32(MemoryLayout<socket_fdinfo>.size))
    }
    guard size == MemoryLayout<socket_fdinfo>.size else { return nil }

    let kindTCP: Int32 = 2  // SOCKINFO_TCP
    let kindIn: Int32 = 1   // SOCKINFO_IN
    switch info.psi.soi_kind {
    case kindTCP:
        return tcpConnection(pid: pid, fd: fd, info: info.psi.soi_proto.pri_tcp)
    case kindIn:
        return udpConnection(pid: pid, fd: fd, info: info.psi.soi_proto.pri_in)
    default:
        return nil  // Unix-domain (4), other kinds — deferred to M4.2
    }
}

private func tcpConnection(pid: pid_t, fd: Int32, info: tcp_sockinfo) -> Connection? {
    let ip = info.tcpsi_ini
    guard let family = decodeFamily(vflag: ip.insi_vflag) else { return nil }
    let localAddress = decodeAddress(insi: ip, side: .local, family: family)
    let localPort = decodePort(rawPort: ip.insi_lport)
    let foreignPort = decodePort(rawPort: ip.insi_fport)
    let remoteAddress = isRemoteUnconnected(insi: ip, family: family)
        ? nil
        : decodeAddress(insi: ip, side: .remote, family: family)
    let remotePort = remoteAddress == nil ? nil : foreignPort
    let tcpState = TCPState.from(rawTcpState: info.tcpsi_state)
    return Connection(
        pid: pid,
        fd: fd,
        family: family,
        protocol: .tcp,
        localAddress: localAddress,
        localPort: localPort,
        remoteAddress: remoteAddress,
        remotePort: remotePort,
        tcpState: tcpState
    )
}

private func udpConnection(pid: pid_t, fd: Int32, info: in_sockinfo) -> Connection? {
    guard let family = decodeFamily(vflag: info.insi_vflag) else { return nil }
    let localAddress = decodeAddress(insi: info, side: .local, family: family)
    let localPort = decodePort(rawPort: info.insi_lport)
    let foreignPort = decodePort(rawPort: info.insi_fport)
    let remoteAddress = isRemoteUnconnected(insi: info, family: family)
        ? nil
        : decodeAddress(insi: info, side: .remote, family: family)
    let remotePort = remoteAddress == nil ? nil : foreignPort
    return Connection(
        pid: pid,
        fd: fd,
        family: family,
        protocol: .udp,
        localAddress: localAddress,
        localPort: localPort,
        remoteAddress: remoteAddress,
        remotePort: remotePort,
        tcpState: nil
    )
}

private enum AddressSide { case local, remote }

private func decodeFamily(vflag: UInt8) -> AddressFamily? {
    if vflag & 0x01 != 0 { return .ipv4 }
    if vflag & 0x02 != 0 { return .ipv6 }
    return nil
}

private func decodePort(rawPort: Int32) -> UInt16? {
    let port = UInt16(rawPort & 0xFFFF).byteSwapped
    return port == 0 ? nil : port
}

private func decodeAddress(insi: in_sockinfo, side: AddressSide, family: AddressFamily) -> String? {
    switch family {
    case .ipv4:
        switch side {
        case .local:
            var addr = insi.insi_laddr.ina_46.i46a_addr4
            return ipv4String(&addr)
        case .remote:
            var addr = insi.insi_faddr.ina_46.i46a_addr4
            return ipv4String(&addr)
        }
    case .ipv6:
        switch side {
        case .local:
            var addr = insi.insi_laddr.ina_6
            return ipv6String(&addr)
        case .remote:
            var addr = insi.insi_faddr.ina_6
            return ipv6String(&addr)
        }
    }
}

private func ipv4String(_ addr: inout in_addr) -> String? {
    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
    let success = withUnsafePointer(to: &addr) { ptr -> Bool in
        inet_ntop(AF_INET, ptr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil
    }
    return success ? stringFromCString(buffer) : nil
}

private func ipv6String(_ addr: inout in6_addr) -> String? {
    var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
    let success = withUnsafePointer(to: &addr) { ptr -> Bool in
        inet_ntop(AF_INET6, ptr, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil
    }
    return success ? stringFromCString(buffer) : nil
}

private func stringFromCString(_ buffer: [CChar]) -> String? {
    let nullIndex = buffer.firstIndex(of: 0) ?? buffer.endIndex
    let bytes = buffer[..<nullIndex].map { UInt8(bitPattern: $0) }
    return String(bytes: bytes, encoding: .utf8)
}

private func isRemoteUnconnected(insi: in_sockinfo, family: AddressFamily) -> Bool {
    if insi.insi_fport == 0 { return true }
    switch family {
    case .ipv4:
        return insi.insi_faddr.ina_46.i46a_addr4.s_addr == 0
    case .ipv6:
        var addr = insi.insi_faddr.ina_6
        return withUnsafeBytes(of: &addr) { bytes in
            bytes.allSatisfy { $0 == 0 }
        }
    }
}
