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
        let all = try OWNetwork.snapshot()
        for connection in all {
            XCTAssertGreaterThan(connection.pid, 0)
            XCTAssertNotNil(connection.localAddress ?? connection.remoteAddress,
                            "Every captured connection should have at least one endpoint")
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
