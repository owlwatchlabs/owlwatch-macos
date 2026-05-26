import OWNetwork
@testable import OWTriage
import XCTest

final class ServiceGuessTests: XCTestCase {
    func testWellKnownPorts() {
        XCTAssertEqual(serviceGuess(port: 443, proto: .tcp), "https")
        XCTAssertEqual(serviceGuess(port: 80,  proto: .tcp), "http")
        XCTAssertEqual(serviceGuess(port: 53,  proto: .udp), "dns")
        XCTAssertEqual(serviceGuess(port: 22,  proto: .tcp), "ssh")
        XCTAssertEqual(serviceGuess(port: 25,  proto: .tcp), "smtp")
        XCTAssertEqual(serviceGuess(port: 587, proto: .tcp), "smtp")
        XCTAssertEqual(serviceGuess(port: 993, proto: .tcp), "imaps")
        XCTAssertEqual(serviceGuess(port: 995, proto: .tcp), "pop3s")
    }

    func testEphemeralPortReturnsNil() {
        XCTAssertNil(serviceGuess(port: 51234, proto: .tcp))
        XCTAssertNil(serviceGuess(port: 8080,  proto: .tcp))
        XCTAssertNil(serviceGuess(port: 1337,  proto: .tcp))
    }

    func testNilPortReturnsNil() {
        XCTAssertNil(serviceGuess(port: nil, proto: .tcp))
    }

    /// The proto field is captured but currently doesn't change the
    /// answer for any port in the table — DNS reads "dns" whether
    /// over TCP or UDP. Test the invariant so a future refinement
    /// (e.g. distinguishing http on UDP for QUIC) is an explicit
    /// change, not an accident.
    func testProtocolDoesNotChangeKnownPortGuess() {
        XCTAssertEqual(serviceGuess(port: 443, proto: .tcp), "https")
        XCTAssertEqual(serviceGuess(port: 443, proto: .udp), "https")
    }
}
