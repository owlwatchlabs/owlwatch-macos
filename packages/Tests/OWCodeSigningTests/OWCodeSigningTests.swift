import Foundation
@testable import OWCodeSigning
import XCTest

final class OWCodeSigningTests: XCTestCase {
    // MARK: - Smoke tests against real system binaries

    func testInspectBinLsIsAppleFirstParty() throws {
        let sig = try OWCodeSigning.inspect(at: URL(fileURLWithPath: "/bin/ls"))
        XCTAssertTrue(sig.isSigned, "/bin/ls is signed on every supported macOS")
        XCTAssertTrue(sig.isValid, "/bin/ls's signature should be structurally valid")
        XCTAssertEqual(sig.signatureType, .apple, "/bin/ls is a first-party Apple binary")
        XCTAssertEqual(sig.identifier, "com.apple.ls")
        XCTAssertNil(sig.teamIdentifier, "/bin/ls has no Team ID — it's signed by Apple's platform identity")
        XCTAssertNotNil(sig.cdHash)
        XCTAssertNotNil(sig.cdHashHex)
        XCTAssertEqual(sig.cdHashHex?.count, (sig.cdHash?.count ?? 0) * 2)
        XCTAssertTrue(sig.authorities.contains("Software Signing"),
                      "/bin/ls's leaf authority should be 'Software Signing'")
        XCTAssertTrue(sig.authorities.contains("Apple Root CA"),
                      "/bin/ls's chain should terminate at Apple Root CA")
    }

    func testInspectDyldIsAppleFirstParty() throws {
        let sig = try OWCodeSigning.inspect(at: URL(fileURLWithPath: "/usr/lib/dyld"))
        XCTAssertTrue(sig.isSigned)
        XCTAssertTrue(sig.isValid)
        XCTAssertEqual(sig.signatureType, .apple)
    }

    func testInspectXcodeHasTeamIdentifier() throws {
        // Xcode is one of the few apps on a developer's box that's reliably
        // present and reliably signed with a Team ID (Apple's own,
        // 59GAB85EFG). Skip if the user doesn't have Xcode installed.
        let xcodePath = "/Applications/Xcode.app"
        guard FileManager.default.fileExists(atPath: xcodePath) else {
            throw XCTSkip("Xcode not installed at \(xcodePath); skipping")
        }
        let sig = try OWCodeSigning.inspect(at: URL(fileURLWithPath: xcodePath))
        XCTAssertTrue(sig.isSigned)
        XCTAssertTrue(sig.isValid)
        XCTAssertNotNil(sig.teamIdentifier,
                        "Xcode.app should report a Team ID via SecCodeCopySigningInformation")
        XCTAssertTrue(sig.flags.contains(.libraryValidation),
                      "Xcode ships with library-validation enabled")
    }

    // MARK: - Ad-hoc detection

    func testInspectSelfBinaryIsAdhoc() throws {
        // The test bundle's executable is built by SwiftPM and signed
        // ad-hoc by the linker on Apple Silicon. We rely on this for the
        // ad-hoc detection path.
        guard let selfPath = Bundle(for: OWCodeSigningTests.self).executablePath else {
            return XCTFail("Could not determine the test bundle's executable path")
        }
        let sig = try OWCodeSigning.inspect(at: URL(fileURLWithPath: selfPath))
        XCTAssertTrue(sig.isSigned, "Linker-applied ad-hoc still counts as signed")
        XCTAssertEqual(sig.signatureType, .adhoc)
        XCTAssertTrue(sig.flags.contains(.adhoc),
                      "Ad-hoc signatures must set kSecCodeSignatureAdhoc")
        XCTAssertNil(sig.teamIdentifier, "Ad-hoc signatures don't carry a Team ID")
        XCTAssertTrue(sig.authorities.isEmpty,
                      "Ad-hoc signatures don't carry a certificate chain")
    }

    // MARK: - Unsigned detection

    func testInspectUnsignedFileReportsUnsigned() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("owlwatch-unsigned-\(UUID().uuidString).bin")
        try Data("plain bytes\n".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sig = try OWCodeSigning.inspect(at: tmp)
        XCTAssertFalse(sig.isSigned, "Plain bytes have no signature")
        XCTAssertFalse(sig.isValid, "isValid is always false when isSigned is false")
        XCTAssertEqual(sig.signatureType, .unsigned)
        XCTAssertNil(sig.identifier)
        XCTAssertNil(sig.teamIdentifier)
        XCTAssertNil(sig.cdHash)
        XCTAssertTrue(sig.authorities.isEmpty)
    }

    // MARK: - Error paths

    func testInspectNonexistentPathThrowsUnreadable() {
        let path = "/tmp/owlwatch-no-such-file-\(UUID().uuidString)"
        let url = URL(fileURLWithPath: path)
        XCTAssertThrowsError(try OWCodeSigning.inspect(at: url)) { error in
            guard case OWCodeSigningError.unreadable = error else {
                return XCTFail("Expected .unreadable, got \(error)")
            }
        }
    }

    // MARK: - Value-type formatting

    func testCDHashHexLowercaseAndFullLength() {
        let bytes = Data([0x12, 0x05, 0xCA, 0xFE])
        let sig = CodeSignature(
            url: URL(fileURLWithPath: "/tmp/x"),
            isSigned: true,
            isValid: true,
            signatureType: .apple,
            identifier: nil,
            teamIdentifier: nil,
            cdHash: bytes,
            authorities: [],
            flags: [],
            format: nil
        )
        XCTAssertEqual(sig.cdHashHex, "1205cafe")
    }

    func testCDHashHexNilWhenCDHashAbsent() {
        let sig = CodeSignature(
            url: URL(fileURLWithPath: "/tmp/x"),
            isSigned: false,
            isValid: false,
            signatureType: .unsigned,
            identifier: nil,
            teamIdentifier: nil,
            cdHash: nil,
            authorities: [],
            flags: [],
            format: nil
        )
        XCTAssertNil(sig.cdHashHex)
    }

    func testSignatureFlagsSymbolicFormSingleBit() {
        XCTAssertEqual(SignatureFlags.runtime.symbolicForm, "runtime")
        XCTAssertEqual(SignatureFlags.adhoc.symbolicForm, "adhoc")
        XCTAssertEqual(SignatureFlags.libraryValidation.symbolicForm, "library-validation")
    }

    func testSignatureFlagsSymbolicFormCombined() {
        let combined: SignatureFlags = [.runtime, .libraryValidation]
        // Stable order: enumeration order in symbolicForm, not insertion order
        XCTAssertEqual(combined.symbolicForm, "library-validation runtime")
    }

    func testSignatureFlagsSymbolicFormEmpty() {
        XCTAssertEqual(SignatureFlags().symbolicForm, "")
    }

    func testSignatureFlagsRawValues() {
        // These are stable Apple platform constants from <Security/CSCommon.h>.
        // Pinning them protects us against an accidental edit dropping a digit.
        XCTAssertEqual(SignatureFlags.host.rawValue, 0x0001)
        XCTAssertEqual(SignatureFlags.adhoc.rawValue, 0x0002)
        XCTAssertEqual(SignatureFlags.libraryValidation.rawValue, 0x2000)
        XCTAssertEqual(SignatureFlags.runtime.rawValue, 0x10000)
    }
}
