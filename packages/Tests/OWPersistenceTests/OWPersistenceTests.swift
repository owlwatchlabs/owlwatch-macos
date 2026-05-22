import Foundation
@testable import OWPersistence
import XCTest

final class OWPersistenceTests: XCTestCase {
    // MARK: - extractProgram

    func testExtractProgramPrefersProgramKey() {
        let (executable, arguments) = extractProgram(from: [
            "Program": "/usr/bin/foo",
            "ProgramArguments": ["logical-name", "--flag"]
        ])
        XCTAssertEqual(executable, "/usr/bin/foo",
                       "Program key wins when both are present")
        XCTAssertEqual(arguments, ["--flag"],
                       "ProgramArguments[0] is the logical argv[0], we keep [1...]")
    }

    func testExtractProgramFallsBackToProgramArguments() {
        let (executable, arguments) = extractProgram(from: [
            "ProgramArguments": ["/usr/bin/bar", "-x", "value"]
        ])
        XCTAssertEqual(executable, "/usr/bin/bar")
        XCTAssertEqual(arguments, ["-x", "value"])
    }

    func testExtractProgramReturnsNilForEmptyPlist() {
        let (executable, arguments) = extractProgram(from: [:])
        XCTAssertNil(executable)
        XCTAssertEqual(arguments, [])
    }

    // MARK: - extractKeepAlive

    func testExtractKeepAliveBoolTrue() {
        XCTAssertEqual(extractKeepAlive(from: true), .always(true))
        XCTAssertTrue(extractKeepAlive(from: true).isActive)
    }

    func testExtractKeepAliveBoolFalse() {
        XCTAssertEqual(extractKeepAlive(from: false), .always(false))
        XCTAssertFalse(extractKeepAlive(from: false).isActive)
    }

    func testExtractKeepAliveConditionalCrashed() {
        let dict: [String: Any] = ["Crashed": true, "SuccessfulExit": false]
        guard case .conditional(let conditions) = extractKeepAlive(from: dict) else {
            return XCTFail("Expected .conditional")
        }
        XCTAssertEqual(conditions.crashed, true)
        XCTAssertEqual(conditions.successfulExit, false)
        XCTAssertNil(conditions.networkState)
        XCTAssertTrue(conditions.hasAnyCondition)
    }

    func testExtractKeepAliveConditionalPathState() {
        let dict: [String: Any] = ["PathState": ["/tmp/trigger": true]]
        guard case .conditional(let conditions) = extractKeepAlive(from: dict) else {
            return XCTFail("Expected .conditional")
        }
        XCTAssertEqual(conditions.pathState, ["/tmp/trigger": true])
    }

    func testExtractKeepAliveAbsent() {
        XCTAssertEqual(extractKeepAlive(from: nil), .always(false))
    }

    // MARK: - extractCalendarIntervals

    func testCalendarIntervalSingleDict() {
        let value: [String: Any] = ["Hour": 9, "Minute": 30]
        let intervals = extractCalendarIntervals(from: value)
        XCTAssertEqual(intervals.count, 1)
        XCTAssertEqual(intervals.first?.hour, 9)
        XCTAssertEqual(intervals.first?.minute, 30)
        XCTAssertNil(intervals.first?.day)
    }

    func testCalendarIntervalArrayOfDicts() {
        let value: [[String: Any]] = [
            ["Hour": 0, "Minute": 0],
            ["Hour": 12, "Minute": 0]
        ]
        let intervals = extractCalendarIntervals(from: value)
        XCTAssertEqual(intervals.count, 2)
        XCTAssertEqual(intervals[0].hour, 0)
        XCTAssertEqual(intervals[1].hour, 12)
    }

    func testCalendarIntervalAbsent() {
        XCTAssertEqual(extractCalendarIntervals(from: nil), [])
    }

    // MARK: - End-to-end plist parsing

    func testParseFullyPopulatedPlist() throws {
        let plist: [String: Any] = [
            "Label": "com.example.test",
            "ProgramArguments": ["/usr/local/bin/example", "--daemon"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "WatchPaths": ["/tmp/foo", "/tmp/bar"],
            "StartInterval": 300
        ]
        let path = try writeTempPlist(plist)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let service = try XCTUnwrap(
            parseLaunchService(at: path, scope: .userAgent, centralDisabledMap: [:])
        )
        XCTAssertEqual(service.label, "com.example.test")
        XCTAssertEqual(service.executablePath, "/usr/local/bin/example")
        XCTAssertEqual(service.arguments, ["--daemon"])
        XCTAssertTrue(service.runAtLoad)
        XCTAssertEqual(service.keepAlive, .always(true))
        XCTAssertEqual(service.watchPaths, ["/tmp/foo", "/tmp/bar"])
        XCTAssertEqual(service.startInterval, 300)
        XCTAssertFalse(service.isDisabled)
    }

    func testParseDisabledViaInPlistKey() throws {
        let plist: [String: Any] = [
            "Label": "com.example.disabled",
            "ProgramArguments": ["/bin/true"],
            "Disabled": true
        ]
        let path = try writeTempPlist(plist)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let service = try XCTUnwrap(
            parseLaunchService(at: path, scope: .systemAgent, centralDisabledMap: [:])
        )
        XCTAssertTrue(service.isDisabled,
                      "In-plist Disabled=true should mark the service disabled")
    }

    func testParseDisabledViaCentralListOverridesEnabled() throws {
        let plist: [String: Any] = [
            "Label": "com.example.centrally-off",
            "ProgramArguments": ["/bin/true"]
        ]
        let path = try writeTempPlist(plist)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let centralMap = ["com.example.centrally-off": true]
        let service = try XCTUnwrap(
            parseLaunchService(at: path, scope: .systemDaemon, centralDisabledMap: centralMap)
        )
        XCTAssertTrue(service.isDisabled,
                      "Central disabled list should mark the service disabled even if plist doesn't")
    }

    func testParseCentralEnabledOverridesInPlistDisabled() throws {
        // Central listing with `false` means "explicitly NOT disabled" — but
        // we OR the two sources, so an in-plist Disabled=true still wins.
        // This documents the precedence we chose.
        let plist: [String: Any] = [
            "Label": "com.example.split-state",
            "ProgramArguments": ["/bin/true"],
            "Disabled": true
        ]
        let path = try writeTempPlist(plist)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let centralMap = ["com.example.split-state": false]
        let service = try XCTUnwrap(
            parseLaunchService(at: path, scope: .systemDaemon, centralDisabledMap: centralMap)
        )
        XCTAssertTrue(service.isDisabled,
                      "If either source says disabled, we report disabled")
    }

    func testParseKeepAliveDictConditions() throws {
        let plist: [String: Any] = [
            "Label": "com.example.conditional",
            "ProgramArguments": ["/bin/true"],
            "KeepAlive": [
                "AfterInitialDemand": true,
                "SuccessfulExit": false
            ]
        ]
        let path = try writeTempPlist(plist)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let service = try XCTUnwrap(
            parseLaunchService(at: path, scope: .userAgent, centralDisabledMap: [:])
        )
        guard case .conditional(let conditions) = service.keepAlive else {
            return XCTFail("Expected .conditional KeepAlive")
        }
        XCTAssertEqual(conditions.afterInitialDemand, true)
        XCTAssertEqual(conditions.successfulExit, false)
    }

    func testParseMalformedPlistReturnsNil() throws {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("owlwatch-malformed-\(UUID().uuidString).plist")
        try Data("not a plist\n".utf8).write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertNil(parseLaunchService(at: path, scope: .userAgent, centralDisabledMap: [:]),
                     "Malformed plist files should return nil rather than throw")
    }

    func testParseEmptyDictPlistIsEnumerable() throws {
        // Google ships empty `<dict/>` placeholders for some of its
        // updater plists. We surface them with nil Label / nil Program
        // rather than dropping them — a tampered plist is detection signal.
        let path = try writeTempPlist([:])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let service = try XCTUnwrap(
            parseLaunchService(at: path, scope: .userAgent, centralDisabledMap: [:])
        )
        XCTAssertNil(service.label)
        XCTAssertNil(service.executablePath)
        XCTAssertFalse(service.runAtLoad)
    }

    // MARK: - System smoke

    func testLaunchServicesReturnsAtLeastApplePlatformDaemons() {
        let services = OWPersistence.launchServices(in: .platformDaemon)
        XCTAssertFalse(services.isEmpty,
                       "/System/Library/LaunchDaemons should always have at least one Apple plist")
        let withLabels = services.filter { $0.label != nil }
        XCTAssertGreaterThan(withLabels.count, 10,
                             "At least 10 well-formed plists should be present on any real macOS install")
    }

    // MARK: - LaunchScope helpers

    func testLaunchScopeRunsAsRootTrueForDaemons() {
        XCTAssertTrue(LaunchScope.platformDaemon.runsAsRoot)
        XCTAssertTrue(LaunchScope.systemDaemon.runsAsRoot)
        XCTAssertFalse(LaunchScope.platformAgent.runsAsRoot)
        XCTAssertFalse(LaunchScope.systemAgent.runsAsRoot)
        XCTAssertFalse(LaunchScope.userAgent.runsAsRoot)
    }

    func testLaunchScopeDirectoryPaths() {
        XCTAssertEqual(LaunchScope.platformDaemon.directoryPath, "/System/Library/LaunchDaemons")
        XCTAssertEqual(LaunchScope.systemAgent.directoryPath, "/Library/LaunchAgents")
        XCTAssertTrue(LaunchScope.userAgent.directoryPath.hasSuffix("/Library/LaunchAgents"))
    }

    // MARK: - Helpers

    private func writeTempPlist(_ plist: [String: Any]) throws -> String {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("owlwatch-test-\(UUID().uuidString).plist")
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }
}
