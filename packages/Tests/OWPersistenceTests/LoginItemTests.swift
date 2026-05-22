import Darwin
import Foundation
@testable import OWPersistence
import XCTest

final class LoginItemTests: XCTestCase {
    // MARK: - Field-level parsers

    func testParseTypeFieldStandardValues() {
        let (name, raw) = parseTypeField("app (0x2)")
        XCTAssertEqual(name, "app")
        XCTAssertEqual(raw, 0x2)
    }

    func testParseTypeFieldMultiWordName() {
        let (name, raw) = parseTypeField("legacy agent (0x10008)")
        XCTAssertEqual(name, "legacy agent")
        XCTAssertEqual(raw, 0x10008)
    }

    func testParseTypeFieldMalformedReturnsZero() {
        let (_, raw) = parseTypeField("(garbage)")
        XCTAssertEqual(raw, 0, "Unparseable hex should fall back to 0")
    }

    func testParseDispositionFieldFullDisposition() {
        XCTAssertEqual(parseDispositionField("[enabled, allowed, notified] (0xb)"), 0xb)
        XCTAssertEqual(parseDispositionField("[disabled, allowed, not notified] (0x2)"), 0x2)
    }

    func testParseDispositionFieldEmpty() {
        XCTAssertEqual(parseDispositionField(""), 0)
    }

    // MARK: - LoginItemKind classification

    func testLoginItemKindFromKnownRawValues() {
        XCTAssertEqual(LoginItemKind.from(rawName: "app", rawValue: 0x2), .app)
        XCTAssertEqual(LoginItemKind.from(rawName: "login item", rawValue: 0x4), .loginItem)
        XCTAssertEqual(LoginItemKind.from(rawName: "quicklook", rawValue: 0x800), .quicklook)
        XCTAssertEqual(LoginItemKind.from(rawName: "spotlight", rawValue: 0x40), .spotlightImporter)
        XCTAssertEqual(LoginItemKind.from(rawName: "legacy agent", rawValue: 0x10008), .legacyAgent)
    }

    func testLoginItemKindFromUnknownRawValuePreservesName() {
        // A hypothetical future BTM type Apple adds. Detection rules will
        // still be able to match on the raw name even though the enum
        // doesn't recognize it.
        XCTAssertEqual(
            LoginItemKind.from(rawName: "future-thing", rawValue: 0x9999),
            .other(rawName: "future-thing")
        )
    }

    // MARK: - Disposition OptionSet

    func testDispositionSymbolicFormMatchesSfltool() {
        XCTAssertEqual(
            LoginItemDisposition(rawValue: 0xb).symbolicForm,
            "enabled, allowed, notified"
        )
        XCTAssertEqual(
            LoginItemDisposition(rawValue: 0x2).symbolicForm,
            "disabled, allowed, not notified"
        )
        XCTAssertEqual(
            LoginItemDisposition(rawValue: 0x3).symbolicForm,
            "enabled, allowed, not notified"
        )
        XCTAssertEqual(
            LoginItemDisposition(rawValue: 0xa).symbolicForm,
            "disabled, allowed, notified"
        )
    }

    func testIsEnabledShortcut() {
        let item = makeFixtureItem(dispositionRawValue: 0xb)  // enabled, allowed, notified
        XCTAssertTrue(item.isEnabled)
        let disabled = makeFixtureItem(dispositionRawValue: 0xa)  // disabled, allowed, notified
        XCTAssertFalse(disabled.isEnabled)
    }

    // MARK: - End-to-end parser against captured fixture

    func testParserAgainstCapturedFixture() throws {
        let fixture = try loadFixture()
        let items = parseSfltoolDumpbtm(fixture)
        // The captured fixture has 15 items across UID -2, UID 0, UID 501
        // sections. -2 and 0 are typically empty on a single-user box;
        // 501 holds the user's apps + extensions.
        XCTAssertEqual(items.count, 15, "Parser should recover every item in the fixture")
        // Every parsed item must have at least UUID + name (parser drops
        // records missing either).
        for item in items {
            XCTAssertFalse(item.uuid.isEmpty)
            XCTAssertFalse(item.name.isEmpty)
        }
    }

    func testParserRecognizesAppRecord() throws {
        let fixture = try loadFixture()
        let items = parseSfltoolDumpbtm(fixture)
        guard let spotify = items.first(where: { $0.name == "Spotify" }) else {
            return XCTFail("Spotify app record should be present in the fixture")
        }
        XCTAssertEqual(spotify.kind, .app)
        XCTAssertEqual(spotify.kindRawValue, 0x2)
        XCTAssertEqual(spotify.teamIdentifier, "2FNC3A47ZF")
        XCTAssertEqual(spotify.bundleIdentifier, "com.spotify.client")
        XCTAssertEqual(spotify.userId, 501)
        XCTAssertFalse(spotify.isEnabled, "Spotify is disabled in the captured fixture")
    }

    func testParserRecognizesLoginItemRecord() throws {
        let fixture = try loadFixture()
        let items = parseSfltoolDumpbtm(fixture)
        guard let helper = items.first(where: { $0.bundleIdentifier == "com.spotify.client.startuphelper" }) else {
            return XCTFail("Spotify StartUpHelper login-item should be present")
        }
        XCTAssertEqual(helper.kind, .loginItem)
        XCTAssertEqual(helper.kindRawValue, 0x4)
        XCTAssertTrue(helper.isEnabled,
                      "StartUpHelper is enabled — the classic third-party login-item pattern")
        // Login-item helpers have a parent identifier referring to the
        // containing app's BTM record.
        XCTAssertNotNil(helper.parentIdentifier)
    }

    func testParserRecognizesLegacyAgentRecord() throws {
        let fixture = try loadFixture()
        let items = parseSfltoolDumpbtm(fixture)
        // Google's keystone updater appears as a legacy-agent record.
        guard let legacy = items.first(where: { $0.kind == .legacyAgent }) else {
            return XCTFail("Fixture should include at least one legacy-agent record")
        }
        XCTAssertEqual(legacy.kindRawValue, 0x10008)
    }

    // MARK: - Parser robustness

    func testParserOnEmptyInputReturnsEmpty() {
        XCTAssertEqual(parseSfltoolDumpbtm("").count, 0)
    }

    func testParserOnGarbageInputDoesNotCrash() {
        XCTAssertEqual(parseSfltoolDumpbtm("nope\nrandom\nlines\n").count, 0)
    }

    func testParserDropsItemsMissingRequiredFields() {
        // A section with an item that has no UUID or Name should be dropped.
        let input = """
        ========================
         Records for UID 501 : ABC-123
        ========================

         Items:

         #1:
                  Type: app (0x2)
                  URL: file:///Applications/Bogus.app/

        """
        let items = parseSfltoolDumpbtm(input)
        XCTAssertEqual(items.count, 0, "Items without UUID + Name should be dropped silently")
    }

    func testParserHandlesNegativeUIDSection() {
        let input = """
        ========================
         Records for UID -2 : FFFFEEEE-DDDD-CCCC-BBBB-AAAAFFFFFFFE
        ========================

         Items:

         #1:
                  UUID: DEAD-BEEF
                  Name: Placeholder
                  Type: app (0x2)
           Disposition: [enabled, allowed, not notified] (0x3)

        """
        let items = parseSfltoolDumpbtm(input)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].userId, uid_t(bitPattern: -2),
                       "UID -2 should bridge to its uid_t bit pattern (0xFFFFFFFE)")
    }

    // Note: a live-system smoke test for OWPersistence.loginItems() is
    // intentionally NOT included. `sfltool dumpbtm` is non-deterministic
    // under XCTest: observed wall-clock between 5 seconds and 200 seconds
    // for the same input on the same machine. The fixture-based tests above
    // cover the parser deterministically; the live path is exercised via
    // `owlwatch login-items` during manual smoke testing.

    // MARK: - Helpers

    private func loadFixture() throws -> String {
        // #filePath is always absolute under SwiftPM, unlike #file which
        // can be virtualized to a relative path. Required to resolve the
        // sibling Fixtures/ directory reliably.
        let testFile = URL(fileURLWithPath: #filePath)
        let fixturePath = testFile
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/sfltool-dumpbtm-sample.txt")
        return try String(contentsOf: fixturePath, encoding: .utf8)
    }

    private func makeFixtureItem(dispositionRawValue: UInt32) -> LoginItem {
        LoginItem(
            uuid: "TEST", userId: 501, name: "Test",
            developerName: nil, teamIdentifier: nil, bundleIdentifier: nil,
            parentIdentifier: nil, identifier: nil, url: nil,
            kind: .app, kindRawValue: 0x2,
            disposition: LoginItemDisposition(rawValue: dispositionRawValue)
        )
    }
}
