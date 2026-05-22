import Darwin
import Foundation
@testable import OWNetwork
import XCTest

final class OWNetworkTests: XCTestCase {
    // MARK: - Live-socket round-trips

    func testTCPListenerOnLoopbackIsCaptured() throws {
        // Create a TCP listener on 127.0.0.1:0 (kernel-assigned port), then
        // confirm OWNetwork.snapshot(pid:) reports it with the expected
        // shape: ipv4 / tcp / listen / 127.0.0.1 / non-zero port / no peer.
        let listenerFd = try makeTCPListener()
        defer { close(listenerFd) }

        let connections = try OWNetwork.snapshot(pid: getpid())
        guard let connection = connections.first(where: { $0.fd == listenerFd }) else {
            return XCTFail("OWNetwork.snapshot did not include the fd we just bound")
        }

        XCTAssertEqual(connection.family, .ipv4)
        XCTAssertEqual(connection.protocol, .tcp)
        XCTAssertEqual(connection.tcpState, .listen)
        XCTAssertEqual(connection.localAddress, "127.0.0.1")
        XCTAssertNotNil(connection.localPort)
        XCTAssertGreaterThan(connection.localPort ?? 0, 0)
        XCTAssertNil(connection.remoteAddress, "Unconnected listener has no peer address")
        XCTAssertNil(connection.remotePort)
        XCTAssertTrue(connection.isListener)
    }

    func testUDPSocketBoundOnLoopbackIsCaptured() throws {
        let socketFd = try makeUDPSocket()
        defer { close(socketFd) }

        let connections = try OWNetwork.snapshot(pid: getpid())
        guard let connection = connections.first(where: { $0.fd == socketFd }) else {
            return XCTFail("OWNetwork.snapshot did not include the UDP fd")
        }

        XCTAssertEqual(connection.family, .ipv4)
        XCTAssertEqual(connection.protocol, .udp)
        XCTAssertNil(connection.tcpState)
        XCTAssertEqual(connection.localAddress, "127.0.0.1")
        XCTAssertNotNil(connection.localPort)
        XCTAssertNil(connection.remoteAddress)
    }

    func testGlobalSnapshotProducesWellFormedRecords() throws {
        // On any running macOS box mDNSResponder, rapportd, or some other
        // system service is listening — global snapshot should always
        // return at least one socket. We don't assert >0 strictly because
        // a hardened CI image could conceivably have nothing listening;
        // only check the call returns and produces well-formed records.
        //
        // IP sockets always have at least a local address (even `0.0.0.0`).
        // Unix sockets may be fully anonymous (socketpair-style) — both
        // endpoints nil — and that's still a well-formed record.
        let all = try OWNetwork.snapshot()
        for connection in all {
            XCTAssertGreaterThan(connection.pid, 0)
            if connection.family != .unix {
                XCTAssertNotNil(
                    connection.localAddress ?? connection.remoteAddress,
                    "IP connections should expose at least one endpoint"
                )
            }
        }
    }

    // MARK: - Error paths

    func testSnapshotForNonexistentPIDDoesNotCrash() {
        // PID 999999 almost certainly doesn't exist. proc_pidinfo will
        // either return 0 (no fds → empty array) or fail. Either outcome
        // is acceptable; the API just shouldn't crash.
        let result = try? OWNetwork.snapshot(pid: 999_999)
        XCTAssertNotNil(result, "Snapshot of unreachable PID should not crash; either empty or throw")
    }

    // MARK: - TCP state mapping

    func testTCPStateMappingMatchesKernelValues() {
        // These values are stable platform constants from <netinet/tcp_fsm.h>.
        // Pinning them protects us against accidental reordering.
        XCTAssertEqual(TCPState.from(rawTcpState: 0), .closed)
        XCTAssertEqual(TCPState.from(rawTcpState: 1), .listen)
        XCTAssertEqual(TCPState.from(rawTcpState: 4), .established)
        XCTAssertEqual(TCPState.from(rawTcpState: 10), .timeWait)
        XCTAssertNil(TCPState.from(rawTcpState: 99))
    }

    func testTCPStateDisplayNamesAreUppercaseUnderscored() {
        XCTAssertEqual(TCPState.established.displayName, "ESTABLISHED")
        XCTAssertEqual(TCPState.finWait1.displayName, "FIN_WAIT_1")
        XCTAssertEqual(TCPState.synReceived.displayName, "SYN_RCVD")
    }

    // MARK: - isListener computed property

    func testIsListenerForTCPListenIsTrue() {
        let connection = makeTestConnection(protocol: .tcp, tcpState: .listen, remoteAddress: nil)
        XCTAssertTrue(connection.isListener)
    }

    func testIsListenerForTCPEstablishedIsFalse() {
        let connection = makeTestConnection(protocol: .tcp, tcpState: .established, remoteAddress: "1.2.3.4")
        XCTAssertFalse(connection.isListener)
    }

    func testIsListenerForBoundUDPIsTrue() {
        let connection = makeTestConnection(protocol: .udp, tcpState: nil, remoteAddress: nil)
        XCTAssertTrue(connection.isListener)
    }

    func testIsListenerForUDPWithPeerIsFalse() {
        let connection = makeTestConnection(protocol: .udp, tcpState: nil, remoteAddress: "1.2.3.4")
        XCTAssertFalse(connection.isListener)
    }

    func testIsListenerForBoundUnixStreamIsTrue() {
        let connection = Connection(
            pid: 1, fd: 3, family: .unix, protocol: .unixStream,
            localAddress: "/var/run/foo.sock", localPort: nil,
            remoteAddress: nil, remotePort: nil, tcpState: nil
        )
        XCTAssertTrue(connection.isListener)
    }

    func testIsListenerForConnectedUnixStreamIsFalse() {
        let connection = Connection(
            pid: 1, fd: 3, family: .unix, protocol: .unixStream,
            localAddress: nil, localPort: nil,
            remoteAddress: "/var/run/foo.sock", remotePort: nil, tcpState: nil
        )
        XCTAssertFalse(connection.isListener)
    }

    // MARK: - Unix-domain sockets (M4.2)

    func testUnixStreamListenerExposesBoundPath() throws {
        let (fd, path) = try makeUnixStreamListener()
        defer {
            close(fd)
            unlink(path)
        }
        let connections = try OWNetwork.snapshot(pid: getpid())
        guard let connection = connections.first(where: { $0.fd == fd }) else {
            return XCTFail("Bound Unix listener was not surfaced in snapshot")
        }
        XCTAssertEqual(connection.family, .unix)
        XCTAssertEqual(connection.protocol, .unixStream)
        XCTAssertEqual(connection.localAddress, path,
                       "localAddress should be the filesystem path the socket was bound to")
        XCTAssertNil(connection.localPort, "Unix sockets have no port")
        XCTAssertNil(connection.remoteAddress, "Unconnected listener has no peer")
        XCTAssertNil(connection.tcpState, "Unix sockets have no TCP state")
        XCTAssertTrue(connection.isListener)
    }

    func testUnixSocketPairAppearsAsAnonymousConnections() throws {
        let (left, right) = try makeUnixSocketPair()
        defer {
            close(left)
            close(right)
        }
        let connections = try OWNetwork.snapshot(pid: getpid())
        let socketPair = connections.filter { $0.fd == left || $0.fd == right }
        XCTAssertEqual(socketPair.count, 2,
                       "Both halves of the socketpair should be enumerated")
        for connection in socketPair {
            XCTAssertEqual(connection.family, .unix)
            XCTAssertEqual(connection.protocol, .unixStream)
            XCTAssertNil(connection.localAddress,
                         "socketpair ends are anonymous — no bound path")
            XCTAssertNil(connection.remoteAddress,
                         "socketpair peer is also anonymous, so no peer path either")
            XCTAssertFalse(connection.isListener,
                           "Anonymous socketpair ends are not listeners")
        }
    }

    func testUnixProtocolRawValuesUseHyphenForm() {
        // The CLI relies on these raw values for the netstat protocol column.
        XCTAssertEqual(TransportProtocol.unixStream.rawValue, "unix-stream")
        XCTAssertEqual(TransportProtocol.unixDatagram.rawValue, "unix-dgram")
    }

    // MARK: - Helpers

    private func makeTCPListener() throws -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EBADF) }
        var sin = sockaddr_in()
        sin.sin_family = sa_family_t(AF_INET)
        sin.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
        sin.sin_port = 0
        let bindResult = withUnsafePointer(to: &sin) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw POSIXError(.EADDRINUSE)
        }
        guard listen(fd, 1) == 0 else {
            close(fd)
            throw POSIXError(.EOPNOTSUPP)
        }
        return fd
    }

    private func makeUDPSocket() throws -> Int32 {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw POSIXError(.EBADF) }
        var sin = sockaddr_in()
        sin.sin_family = sa_family_t(AF_INET)
        sin.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
        sin.sin_port = 0
        let bindResult = withUnsafePointer(to: &sin) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw POSIXError(.EADDRINUSE)
        }
        return fd
    }

    /// Bind a Unix-domain stream listener at a temp path.
    private func makeUnixStreamListener() throws -> (fd: Int32, path: String) {
        let path = "/tmp/owlwatch-test-\(UUID().uuidString.prefix(8)).sock"
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EBADF) }
        var sun = sockaddr_un()
        sun.sun_family = sa_family_t(AF_UNIX)
        _ = path.withCString { cstr in
            withUnsafeMutablePointer(to: &sun.sun_path) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dst -> Int in
                    _ = strncpy(dst, cstr, 103)
                    return 0
                }
            }
        }
        let bindResult = withUnsafePointer(to: &sun) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw POSIXError(.EADDRINUSE)
        }
        guard listen(fd, 1) == 0 else {
            close(fd)
            unlink(path)
            throw POSIXError(.EOPNOTSUPP)
        }
        return (fd, path)
    }

    /// Create an anonymous Unix-domain socketpair. Returns both fds.
    private func makeUnixSocketPair() throws -> (Int32, Int32) {
        var fds: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else {
            throw POSIXError(.ENOTCONN)
        }
        return (fds[0], fds[1])
    }

    private func makeTestConnection(
        protocol: TransportProtocol,
        tcpState: TCPState?,
        remoteAddress: String?
    ) -> Connection {
        Connection(
            pid: 1,
            fd: 3,
            family: .ipv4,
            protocol: `protocol`,
            localAddress: "127.0.0.1",
            localPort: 12345,
            remoteAddress: remoteAddress,
            remotePort: remoteAddress.map { _ in 80 },
            tcpState: tcpState
        )
    }
}
