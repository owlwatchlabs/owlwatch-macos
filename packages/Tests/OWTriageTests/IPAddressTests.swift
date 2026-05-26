@testable import OWTriage
import XCTest

final class IPAddressTests: XCTestCase {
    // MARK: - IPv4 parsing + ranges

    func testParseDottedDecimal() {
        guard case .v4(let value) = IPAddress("192.168.1.1") else {
            return XCTFail("expected v4")
        }
        // 192.168.1.1 = 0xC0A80101
        XCTAssertEqual(value, 0xC0A8_0101)
    }

    func testRejectsInvalidV4() {
        XCTAssertNil(IPAddress("999.0.0.1"))
        XCTAssertNil(IPAddress("1.2.3"))
        XCTAssertNil(IPAddress("1.2.3.4.5"))
        XCTAssertNil(IPAddress("hello"))
    }

    func testV4LoopbackRange() {
        XCTAssertTrue(IPAddress("127.0.0.1")!.isLoopback)
        XCTAssertTrue(IPAddress("127.255.255.254")!.isLoopback)
        XCTAssertFalse(IPAddress("128.0.0.1")!.isLoopback)
        XCTAssertFalse(IPAddress("126.255.255.255")!.isLoopback)
    }

    func testV4PrivateRanges() {
        // 10/8
        XCTAssertTrue(IPAddress("10.0.0.1")!.isPrivate)
        XCTAssertTrue(IPAddress("10.255.255.254")!.isPrivate)
        // 172.16/12 — boundary check
        XCTAssertTrue(IPAddress("172.16.0.1")!.isPrivate)
        XCTAssertTrue(IPAddress("172.31.255.254")!.isPrivate)
        XCTAssertFalse(IPAddress("172.15.255.255")!.isPrivate)
        XCTAssertFalse(IPAddress("172.32.0.0")!.isPrivate)
        // 192.168/16
        XCTAssertTrue(IPAddress("192.168.1.1")!.isPrivate)
        XCTAssertFalse(IPAddress("192.169.1.1")!.isPrivate)
        // Public
        XCTAssertFalse(IPAddress("8.8.8.8")!.isPrivate)
        XCTAssertFalse(IPAddress("104.21.45.18")!.isPrivate)
    }

    func testV4LinkLocal() {
        XCTAssertTrue(IPAddress("169.254.1.1")!.isLinkLocal)
        XCTAssertFalse(IPAddress("169.255.1.1")!.isLinkLocal)
        XCTAssertFalse(IPAddress("170.254.1.1")!.isLinkLocal)
    }

    // MARK: - IPv6 parsing + ranges

    func testParseCompressedV6() {
        guard case .v6(let groups) = IPAddress("::1") else {
            return XCTFail("expected v6")
        }
        XCTAssertEqual(groups, [0, 0, 0, 0, 0, 0, 0, 1])
    }

    func testParseFullV6() {
        let ip = IPAddress("2001:0db8:85a3:0000:0000:8a2e:0370:7334")
        guard case .v6(let groups) = ip else { return XCTFail("expected v6") }
        XCTAssertEqual(groups, [0x2001, 0x0db8, 0x85a3, 0, 0, 0x8a2e, 0x0370, 0x7334])
    }

    func testParseCompressedTrailing() {
        let ip = IPAddress("fe80::")
        guard case .v6(let groups) = ip else { return XCTFail("expected v6") }
        XCTAssertEqual(groups, [0xfe80, 0, 0, 0, 0, 0, 0, 0])
    }

    func testV6LoopbackIsOnlyDoubleColonOne() {
        XCTAssertTrue(IPAddress("::1")!.isLoopback)
        XCTAssertFalse(IPAddress("::2")!.isLoopback)
        XCTAssertFalse(IPAddress("fe80::1")!.isLoopback)
    }

    func testV6LinkLocalRange() {
        // fe80::/10 covers fe80…febf in the first group
        XCTAssertTrue(IPAddress("fe80::1")!.isLinkLocal)
        XCTAssertTrue(IPAddress("febf::ffff")!.isLinkLocal)
        XCTAssertFalse(IPAddress("fec0::1")!.isLinkLocal)
        XCTAssertFalse(IPAddress("fe7f::1")!.isLinkLocal)
    }

    func testV6UniqueLocalRange() {
        // fc00::/7 covers fc00…fdff
        XCTAssertTrue(IPAddress("fc00::1")!.isPrivate)
        XCTAssertTrue(IPAddress("fd00::ffff")!.isPrivate)
        XCTAssertFalse(IPAddress("fb00::1")!.isPrivate)
        XCTAssertFalse(IPAddress("fe00::1")!.isPrivate)
    }

    func testRejectsDoubleDoubleColon() {
        XCTAssertNil(IPAddress("fe80::1::2"))
    }
}
