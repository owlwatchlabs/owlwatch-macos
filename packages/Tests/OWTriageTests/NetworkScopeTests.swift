import OWNetwork
@testable import OWTriage
import XCTest

final class NetworkScopeTests: XCTestCase {
    func testPublicIPv4IsInternet() {
        let conn = makeConnection(remoteAddress: "104.21.45.18")
        XCTAssertEqual(NetworkScope(conn), .internetPublic)
    }

    func testPublicIPv6IsInternet() {
        let conn = makeConnection(family: .ipv6, remoteAddress: "2606:4700::1111")
        XCTAssertEqual(NetworkScope(conn), .internetPublic)
    }

    func testRFC1918IsLAN() {
        XCTAssertEqual(NetworkScope(makeConnection(remoteAddress: "10.0.0.1")), .lan)
        XCTAssertEqual(NetworkScope(makeConnection(remoteAddress: "172.20.0.1")), .lan)
        XCTAssertEqual(NetworkScope(makeConnection(remoteAddress: "192.168.1.42")), .lan)
    }

    func testIPv6UniqueLocalIsLAN() {
        let conn = makeConnection(family: .ipv6, remoteAddress: "fc00::1")
        XCTAssertEqual(NetworkScope(conn), .lan)
    }

    func testLinkLocalIsLAN() {
        XCTAssertEqual(
            NetworkScope(makeConnection(remoteAddress: "169.254.1.1")),
            .lan
        )
        XCTAssertEqual(
            NetworkScope(makeConnection(family: .ipv6, remoteAddress: "fe80::1")),
            .lan
        )
    }

    func testLoopback() {
        XCTAssertEqual(
            NetworkScope(makeConnection(remoteAddress: "127.0.0.1")),
            .localhost
        )
        XCTAssertEqual(
            NetworkScope(makeConnection(family: .ipv6, remoteAddress: "::1")),
            .localhost
        )
    }

    func testUnixSocketIsIPC() {
        let conn = makeConnection(family: .unix, protocol: .unixStream,
                                  remoteAddress: "/tmp/some.sock")
        XCTAssertEqual(NetworkScope(conn), .ipc)
    }

    func testUnixListenerWithEmptyRemoteIsStillIPC() {
        // Unix sockets often have nil remote (the family alone
        // tells us it's IPC).
        let conn = makeConnection(family: .unix, protocol: .unixStream,
                                  remoteAddress: nil)
        XCTAssertEqual(NetworkScope(conn), .ipc)
    }

    func testListenerWithNoRemoteCollapsesToUnknown() {
        // TCP listener: family ipv4, no remote — there's nothing to
        // classify. Caller renders listeners via Connection.isListener.
        let conn = makeConnection(remoteAddress: nil)
        XCTAssertEqual(NetworkScope(conn), .unknown)
    }

    func testGarbageRemoteIsUnknown() {
        let conn = makeConnection(remoteAddress: "not-an-ip")
        XCTAssertEqual(NetworkScope(conn), .unknown)
    }

    // MARK: - Helper

    private func makeConnection(
        family: AddressFamily = .ipv4,
        protocol proto: TransportProtocol = .tcp,
        remoteAddress: String?
    ) -> Connection {
        Connection(
            pid: 1, fd: 1,
            family: family, protocol: proto,
            localAddress: nil, localPort: nil,
            remoteAddress: remoteAddress, remotePort: nil,
            tcpState: nil
        )
    }
}
