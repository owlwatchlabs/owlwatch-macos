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

    // MARK: - Designated requirement (M3.2)

    func testInspectBinLsDesignatedRequirement() throws {
        let sig = try OWCodeSigning.inspect(at: URL(fileURLWithPath: "/bin/ls"))
        // The DR for /bin/ls is stable across macOS versions: identifier pin
        // + anchor apple. The exact whitespace from SecRequirementCopyString
        // is also stable, but match loosely to survive future formatting
        // tweaks.
        let requirement = try XCTUnwrap(sig.designatedRequirement, "/bin/ls should expose a DR")
        XCTAssertTrue(requirement.contains("identifier \"com.apple.ls\""))
        XCTAssertTrue(requirement.contains("anchor apple"))
    }

    func testUnsignedFileHasNoDesignatedRequirement() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("owlwatch-unsigned-dr-\(UUID().uuidString).bin")
        try Data("plain bytes\n".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let sig = try OWCodeSigning.inspect(at: tmp)
        XCTAssertNil(sig.designatedRequirement)
    }

    // MARK: - Hardened runtime version (M3.2)

    func testInspectBinLsHasNoHardenedRuntime() throws {
        let sig = try OWCodeSigning.inspect(at: URL(fileURLWithPath: "/bin/ls"))
        XCTAssertFalse(sig.hasHardenedRuntime,
                       "/bin/ls is not built with the hardened runtime")
        XCTAssertNil(sig.hardenedRuntimeVersion,
                     "hardenedRuntimeVersion should only be populated when the runtime flag is set")
    }

    func testRectangleHasHardenedRuntimeAndStapledNotarization() throws {
        // Rectangle is a small, open-source, Developer-ID-signed and
        // stapled-notarized app. If the user has it installed, it's our
        // canonical "full Developer ID release" fixture.
        let path = "/Applications/Rectangle.app"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Rectangle.app not installed at \(path); skipping")
        }
        let sig = try OWCodeSigning.inspect(at: URL(fileURLWithPath: path))
        XCTAssertEqual(sig.signatureType, .developerID)
        XCTAssertTrue(sig.hasHardenedRuntime, "Rectangle ships with hardened runtime")
        let version = try XCTUnwrap(sig.hardenedRuntimeVersion)
        // Format must be exactly three dotted numeric segments.
        let parts = version.split(separator: ".")
        XCTAssertEqual(parts.count, 3, "Runtime version should be 'X.Y.Z'")
        XCTAssertTrue(parts.allSatisfy { Int($0) != nil })
        XCTAssertTrue(sig.isStapledForNotarization,
                      "Rectangle.app ships a stapled notarization ticket")
        XCTAssertNotNil(sig.stapledNotarizationTicket)
        XCTAssertGreaterThan(sig.stapledNotarizationTicket?.count ?? 0, 100,
                             "A real stapled ticket is at least a few hundred bytes")
    }

    // MARK: - Notarization detection (M3.2)

    func testBinLsHasNoStapledTicket() throws {
        // System binaries are not notarized — they ship with the OS.
        let sig = try OWCodeSigning.inspect(at: URL(fileURLWithPath: "/bin/ls"))
        XCTAssertFalse(sig.isStapledForNotarization)
        XCTAssertNil(sig.stapledNotarizationTicket)
    }

    func testUnsignedFileHasNoStapledTicket() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("owlwatch-unsigned-staple-\(UUID().uuidString).bin")
        try Data("plain bytes\n".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let sig = try OWCodeSigning.inspect(at: tmp)
        XCTAssertFalse(sig.isStapledForNotarization)
    }

    // MARK: - Entitlements (M3.3)

    func testBinLsHasNoEntitlementsBlob() throws {
        // /bin/ls is a system tool without an entitlements blob at all —
        // distinct from "blob present but empty" (Rectangle's case).
        let sig = try OWCodeSigning.inspect(at: URL(fileURLWithPath: "/bin/ls"))
        XCTAssertNil(sig.entitlements,
                     "/bin/ls should have no entitlements blob (nil, not empty dict)")
    }

    func testRectangleHasEmptyEntitlementsBlob() throws {
        // Rectangle.app embeds an entitlements blob that parses to an empty
        // dict — confirmed via `codesign -d --entitlements -` which prints
        // `[Dict]`. Tests the three-state distinction: nil vs [:] vs
        // populated.
        let path = "/Applications/Rectangle.app"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Rectangle.app not installed; skipping")
        }
        let sig = try OWCodeSigning.inspect(at: URL(fileURLWithPath: path))
        let entitlements = try XCTUnwrap(sig.entitlements,
                                         "Rectangle should expose an entitlements blob")
        XCTAssertTrue(entitlements.isEmpty,
                      "Rectangle's blob is structurally present but contains no entries")
    }

    func testVSCodeHasHardenedRuntimeEntitlements() throws {
        // VS Code's entitlements are stable, named, and small enough to
        // assert against. They're all booleans set to true.
        let path = "/Applications/Visual Studio Code.app"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("VS Code not installed; skipping")
        }
        let sig = try OWCodeSigning.inspect(at: URL(fileURLWithPath: path))
        let entitlements = try XCTUnwrap(sig.entitlements)
        XCTAssertFalse(entitlements.isEmpty)
        XCTAssertEqual(entitlements["com.apple.security.cs.allow-jit"]?.boolValue, true,
                       "VS Code requires JIT for Electron's V8")
    }

    func testUnsignedFileHasNoEntitlementsBlob() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("owlwatch-unsigned-ents-\(UUID().uuidString).bin")
        try Data("plain bytes\n".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let sig = try OWCodeSigning.inspect(at: tmp)
        XCTAssertNil(sig.entitlements)
    }
}
