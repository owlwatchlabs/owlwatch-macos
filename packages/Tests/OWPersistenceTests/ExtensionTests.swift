import Foundation
@testable import OWPersistence
import XCTest

final class ExtensionTests: XCTestCase {
    // MARK: - SystemExtensionCategory mapping

    func testCategoryMappingForKnownStrings() {
        XCTAssertEqual(
            SystemExtensionCategory.from(rawValue: "com.apple.system_extension.network_extension"),
            .networkExtension
        )
        XCTAssertEqual(
            SystemExtensionCategory.from(rawValue: "com.apple.system_extension.endpoint_security"),
            .endpointSecurity
        )
        XCTAssertEqual(
            SystemExtensionCategory.from(rawValue: "com.apple.system_extension.driver"),
            .driver
        )
    }

    func testCategoryMappingPreservesUnknownRaw() {
        let cat = SystemExtensionCategory.from(rawValue: "com.apple.system_extension.future_kind")
        XCTAssertEqual(cat, .other(rawValue: "com.apple.system_extension.future_kind"))
        XCTAssertEqual(cat.rawValue, "com.apple.system_extension.future_kind")
    }

    // MARK: - SystemExtensionState mapping

    func testStateMappingForKnownStrings() {
        XCTAssertEqual(SystemExtensionState.from(rawValue: "activated_enabled"), .activatedEnabled)
        XCTAssertEqual(SystemExtensionState.from(rawValue: "activated_disabled"), .activatedDisabled)
        XCTAssertEqual(SystemExtensionState.from(rawValue: "awaiting_user_approval"), .awaitingUserApproval)
        XCTAssertEqual(SystemExtensionState.from(rawValue: "staged"), .staged)
        XCTAssertEqual(
            SystemExtensionState.from(rawValue: "terminated_waiting_to_uninstall"),
            .terminatedWaitingToUninstall
        )
    }

    func testStateMappingPreservesUnknownRaw() {
        XCTAssertEqual(
            SystemExtensionState.from(rawValue: "future_state"),
            .other(rawValue: "future_state")
        )
    }

    func testIsRunningOnlyForActivatedEnabled() {
        XCTAssertTrue(SystemExtensionState.activatedEnabled.isRunning)
        XCTAssertFalse(SystemExtensionState.activatedDisabled.isRunning)
        XCTAssertFalse(SystemExtensionState.awaitingUserApproval.isRunning)
        XCTAssertFalse(SystemExtensionState.staged.isRunning)
    }

    // MARK: - db.plist parser against synthetic fixture

    func testParseFixtureExtractsAllThreeRecords() throws {
        let extensions = parseSystemExtensionDB(at: fixturePath())
        XCTAssertEqual(extensions.count, 3, "Fixture has 3 extensions")
    }

    func testParseFixtureEndpointSecurityRecord() throws {
        let extensions = parseSystemExtensionDB(at: fixturePath())
        let bundleID = "com.owlwatchlabs.owlwatch.endpoint"
        guard let owlwatch = extensions.first(where: { $0.bundleIdentifier == bundleID }) else {
            return XCTFail("Endpoint Security record missing from fixture parse")
        }
        XCTAssertEqual(owlwatch.teamIdentifier, "ABCDEFGHIJ")
        XCTAssertEqual(owlwatch.shortVersion, "1.0")
        XCTAssertEqual(owlwatch.bundleVersion, "42")
        XCTAssertEqual(owlwatch.state, .activatedEnabled)
        XCTAssertEqual(owlwatch.categories, [.endpointSecurity])
        XCTAssertEqual(owlwatch.uniqueID, "11111111-2222-3333-4444-555555555555")
    }

    func testParseFixtureAwaitingApprovalRecord() throws {
        let extensions = parseSystemExtensionDB(at: fixturePath())
        guard let vpn = extensions.first(where: { $0.bundleIdentifier == "com.example.vpn" }) else {
            return XCTFail("VPN record missing")
        }
        XCTAssertEqual(vpn.state, .awaitingUserApproval)
        XCTAssertEqual(vpn.categories, [.networkExtension])
        XCTAssertFalse(vpn.state.isRunning,
                       "awaiting_user_approval should not be classified as running")
    }

    func testParseFixtureDriverRecord() throws {
        let extensions = parseSystemExtensionDB(at: fixturePath())
        guard let driver = extensions.first(where: { $0.bundleIdentifier == "com.example.driver" }) else {
            return XCTFail("Driver record missing")
        }
        XCTAssertEqual(driver.categories, [.driver])
        XCTAssertEqual(driver.state, .activatedDisabled)
    }

    // MARK: - Robustness

    func testParseMissingFileReturnsEmpty() {
        let extensions = parseSystemExtensionDB(at: "/var/empty/nonexistent.plist")
        XCTAssertEqual(extensions, [])
    }

    func testParseMalformedPlistReturnsEmpty() throws {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("owlwatch-bad-sysext-\(UUID().uuidString).plist")
        try Data("not a plist\n".utf8).write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertEqual(parseSystemExtensionDB(at: path), [])
    }

    func testParseEntryMissingRequiredFieldsReturnsNil() {
        // entries without `identifier` or `bundlePath` are dropped.
        XCTAssertNil(parseSystemExtensionEntry(["state": "activated_enabled"]))
        XCTAssertNil(parseSystemExtensionEntry(["identifier": "com.foo"]))
    }

    // MARK: - Kernel extension parsing — live smoke

    func testKernelExtensionsLivePlatformScopeNonEmpty() {
        let extensions = OWPersistence.kernelExtensions(in: .platform)
        XCTAssertFalse(extensions.isEmpty,
                       "/System/Library/Extensions is non-empty on every supported macOS")
        // Most platform kexts have a CFBundleIdentifier.
        let withIDs = extensions.filter { $0.bundleIdentifier != nil }
        XCTAssertGreaterThan(withIDs.count, 100,
                             "At least 100 platform kexts should have bundle IDs")
    }

    func testKernelExtensionsLiveScopeAttributionIsCorrect() {
        let platform = OWPersistence.kernelExtensions(in: .platform)
        let system = OWPersistence.kernelExtensions(in: .system)
        for ext in platform {
            XCTAssertEqual(ext.scope, .platform)
            XCTAssertTrue(ext.bundlePath.hasPrefix("/System/Library/Extensions"))
        }
        for ext in system {
            XCTAssertEqual(ext.scope, .system)
            XCTAssertTrue(ext.bundlePath.hasPrefix("/Library/Extensions"))
        }
    }

    func testKernelExtensionsExecutablePathConstruction() {
        let extensions = OWPersistence.kernelExtensions(in: .platform).prefix(20)
        let withExecutables = extensions.filter { $0.executablePath != nil }
        XCTAssertFalse(withExecutables.isEmpty,
                       "Most platform kexts have an executable")
        for ext in withExecutables {
            guard let path = ext.executablePath, let name = ext.executableName else {
                return XCTFail("withExecutables should have both fields populated")
            }
            XCTAssertTrue(path.hasSuffix("Contents/MacOS/\(name)"),
                          "executablePath should be bundlePath + /Contents/MacOS/CFBundleExecutable")
        }
    }

    func testParseKernelExtensionFromBundleWithMissingInfoReturnsNil() {
        // A directory that's named .kext but has no Contents/Info.plist
        // should not parse — the parser returns nil.
        let bogusPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("Bogus-\(UUID().uuidString).kext")
        try? FileManager.default.createDirectory(
            atPath: bogusPath, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(atPath: bogusPath) }
        XCTAssertNil(parseKernelExtension(at: bogusPath, scope: .system))
    }

    // MARK: - Helpers

    private func fixturePath() -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/system-extensions-db.plist")
            .path
    }
}
