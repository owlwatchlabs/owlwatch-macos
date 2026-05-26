import Foundation
import OWCodeSigning
@testable import OWTriage
import XCTest

final class SignerTests: XCTestCase {
    /// `nil` and `isSigned == false` collapse to `.unsigned` — the
    /// safe-default for triage.
    func testNilSignatureCollapsesToUnsigned() {
        XCTAssertEqual(Signer(nil), .unsigned)
    }

    func testApplePlatformBinary() {
        let sig = makeSignature(type: .apple)
        XCTAssertEqual(Signer(sig), .apple)
    }

    func testAppleDeveloperLocalBuild() {
        let sig = makeSignature(type: .appleDeveloper)
        XCTAssertEqual(Signer(sig), .apple)
    }

    func testDeveloperIDIsThirdParty() {
        let sig = makeSignature(type: .developerID)
        XCTAssertEqual(Signer(sig), .developerID)
    }

    func testAppStoreIsThirdParty() {
        let sig = makeSignature(type: .appStore)
        XCTAssertEqual(Signer(sig), .developerID)
    }

    func testAdhocClassifiesAsUnsigned() {
        let sig = makeSignature(type: .adhoc)
        XCTAssertEqual(Signer(sig), .unsigned)
    }

    func testExplicitlyUnsignedClassifiesAsUnsigned() {
        let sig = makeSignature(type: .unsigned, isSigned: false)
        XCTAssertEqual(Signer(sig), .unsigned)
    }

    func testInvalidSignatureCollapsesToUnsigned() {
        // A structurally invalid signature is as alarming as no
        // signature — the verdict is the same.
        let sig = makeSignature(type: .developerID, isValid: false)
        XCTAssertEqual(Signer(sig), .unsigned)
    }

    func testUnknownAuthority() {
        let sig = makeSignature(type: .unknown)
        XCTAssertEqual(Signer(sig), .unknown)
    }

    func testLabelStrings() {
        XCTAssertEqual(Signer.apple.label, "Apple")
        XCTAssertEqual(Signer.developerID.label, "Developer ID")
        XCTAssertEqual(Signer.unsigned.label, "unsigned")
        XCTAssertEqual(Signer.unknown.label, "unknown")
    }

    // MARK: - Helpers

    private func makeSignature(
        type: SignatureType,
        isSigned: Bool = true,
        isValid: Bool = true
    ) -> CodeSignature {
        CodeSignature(
            url: URL(fileURLWithPath: "/test"),
            isSigned: isSigned,
            isValid: isValid,
            signatureType: type,
            identifier: nil,
            teamIdentifier: nil,
            cdHash: nil,
            authorities: [],
            flags: SignatureFlags(rawValue: 0),
            format: nil
        )
    }
}
