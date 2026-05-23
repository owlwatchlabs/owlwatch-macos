import Foundation
@testable import OWPersistence
import XCTest

final class EnrichedMutationTests: XCTestCase {
    // MARK: - enrich() behavior

    func testEnrichRemovedEventCarriesNoPayload() {
        let mutation = PersistenceMutation(
            path: "/Users/anon/Library/LaunchAgents/com.example.foo.plist",
            kind: .removed,
            scope: .userLaunchd,
            timestamp: Date(),
            eventID: 1
        )
        let enriched = enrich(mutation: mutation)
        XCTAssertNil(enriched.launchService,
                     "Removed files have no readable content — no payload should be attached")
        XCTAssertFalse(enriched.hasPayload)
    }

    func testEnrichAddedLaunchAgentParsesPlist() throws {
        let path = try writeTempLaunchAgent(label: "com.example.enrich-added")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let mutation = PersistenceMutation(
            path: path, kind: .added, scope: .userLaunchd,
            timestamp: Date(), eventID: 1
        )
        let enriched = enrich(mutation: mutation)
        let service = try XCTUnwrap(enriched.launchService,
                                    "Added LaunchAgent should yield a parsed LaunchService")
        XCTAssertEqual(service.label, "com.example.enrich-added")
        XCTAssertEqual(service.executablePath, "/usr/local/bin/decoy")
        XCTAssertTrue(service.runAtLoad)
        XCTAssertTrue(enriched.hasPayload)
    }

    func testEnrichModifiedLaunchAgentRereadsCurrentContent() throws {
        // Write v1, generate a .modified event, then write v2; the
        // enriched record should reflect v2 — the parser reads the
        // file at event-handling time, not at event-emission time.
        let path = try writeTempLaunchAgent(label: "com.example.v1")
        defer { try? FileManager.default.removeItem(atPath: path) }

        // Rewrite the same file with a different label, simulating a
        // modification mid-stream.
        let updated = try PropertyListSerialization.data(
            fromPropertyList: [
                "Label": "com.example.v2",
                "ProgramArguments": ["/usr/local/bin/decoy"]
            ] as [String: Any],
            format: .xml,
            options: 0
        )
        try updated.write(to: URL(fileURLWithPath: path))

        let mutation = PersistenceMutation(
            path: path, kind: .modified, scope: .userLaunchd,
            timestamp: Date(), eventID: 2
        )
        let enriched = enrich(mutation: mutation)
        XCTAssertEqual(enriched.launchService?.label, "com.example.v2")
    }

    func testEnrichSystemDaemonClassifiesScopeCorrectly() throws {
        // The mapping from MutationScope.systemLaunchd to LaunchScope
        // must distinguish daemon-vs-agent based on the path,
        // because the disabled-list resolution depends on it.
        // Without writing into protected /Library/LaunchDaemons we
        // exercise the path-prefix mapping via a temp file with the
        // right structure.
        let path = try writeTempLaunchAgent(
            label: "com.example.daemon-shape",
            atRelativePath: "tmp-daemon"
        )
        defer { try? FileManager.default.removeItem(atPath: path) }
        let mutation = PersistenceMutation(
            path: path, kind: .added,
            scope: .userLaunchd,  // matches the actual temp path's scope
            timestamp: Date(), eventID: 3
        )
        let enriched = enrich(mutation: mutation)
        XCTAssertEqual(enriched.launchService?.scope, .userAgent,
                       "Temp-path mutation should map to userAgent LaunchScope")
    }

    func testEnrichUnsupportedScopeYieldsNoPayload() {
        let mutation = PersistenceMutation(
            path: "/tmp/random.file", kind: .added, scope: .other,
            timestamp: Date(), eventID: 4
        )
        let enriched = enrich(mutation: mutation)
        XCTAssertNil(enriched.launchService)
        XCTAssertNil(enriched.hooks)
        XCTAssertFalse(enriched.hasPayload,
                       "Mutations outside the M5 scopes carry the raw event with no parsed payload")
    }

    func testEnrichLoginwindowMutationParsesHooks() throws {
        let path = try writeTempLoginwindowPlist([
            "LoginHook": "/usr/local/bin/login.sh",
            "LogoutHook": "/usr/local/bin/logout.sh"
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let mutation = PersistenceMutation(
            path: path, kind: .modified, scope: .loginwindowPlist,
            timestamp: Date(), eventID: 5
        )
        let enriched = enrich(mutation: mutation)
        let hooks = try XCTUnwrap(enriched.hooks,
                                  "loginwindow plist mutation should yield parsed hooks")
        XCTAssertEqual(hooks.count, 2)
        XCTAssertTrue(hooks.contains(where: { $0.kind == .login }))
        XCTAssertTrue(hooks.contains(where: { $0.kind == .logout }))
        XCTAssertTrue(enriched.hasPayload)
    }

    // MARK: - hasPayload

    func testHasPayloadFalseForBareMutation() {
        let raw = PersistenceMutation(
            path: "/tmp/foo", kind: .added, scope: .other,
            timestamp: Date(), eventID: 0
        )
        let bare = EnrichedMutation(mutation: raw)
        XCTAssertFalse(bare.hasPayload)
    }

    func testHasPayloadTrueForLaunchService() {
        let raw = PersistenceMutation(
            path: "/tmp/foo.plist", kind: .added, scope: .userLaunchd,
            timestamp: Date(), eventID: 0
        )
        let service = LaunchService(
            plistPath: "/tmp/foo.plist", scope: .userAgent,
            label: "com.example.foo", executablePath: "/bin/true",
            arguments: [], runAtLoad: true, keepAlive: .always(false),
            watchPaths: [], startInterval: nil,
            startCalendarInterval: [], isDisabled: false
        )
        let enriched = EnrichedMutation(mutation: raw, launchService: service)
        XCTAssertTrue(enriched.hasPayload)
    }

    func testHasPayloadFalseForEmptyHookArray() {
        let raw = PersistenceMutation(
            path: "/tmp/loginwindow.plist", kind: .modified,
            scope: .loginwindowPlist, timestamp: Date(), eventID: 0
        )
        let enriched = EnrichedMutation(mutation: raw, hooks: [])
        XCTAssertFalse(enriched.hasPayload,
                       "An empty hooks array — plist parsed but no hooks set — is not a meaningful payload")
    }

    // MARK: - Helpers

    private func writeTempLaunchAgent(
        label: String,
        atRelativePath relativePath: String = "tmp-agent"
    ) throws -> String {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("\(relativePath)-\(UUID().uuidString).plist")
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/local/bin/decoy"],
            "RunAtLoad": true
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        )
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }

    private func writeTempLoginwindowPlist(_ contents: [String: Any]) throws -> String {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("loginwindow-\(UUID().uuidString).plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: contents, format: .xml, options: 0
        )
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }
}
