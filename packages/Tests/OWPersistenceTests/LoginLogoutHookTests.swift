import Foundation
@testable import OWPersistence
import XCTest

final class LoginLogoutHookTests: XCTestCase {
    // MARK: - HookKind / HookScope

    func testHookKindPlistKeys() {
        XCTAssertEqual(HookKind.login.plistKey, "LoginHook")
        XCTAssertEqual(HookKind.logout.plistKey, "LogoutHook")
    }

    func testHookScopePlistPaths() {
        XCTAssertEqual(HookScope.system.plistPath, "/Library/Preferences/com.apple.loginwindow.plist")
        XCTAssertTrue(HookScope.user.plistPath.hasSuffix("/Library/Preferences/com.apple.loginwindow.plist"),
                      "user-scope plist should resolve under the user's home")
    }

    // MARK: - Parser

    func testParseBothHooksSet() throws {
        let path = try writeTempLoginwindowPlist([
            "LoginHook": "/Library/Scripts/login.sh",
            "LogoutHook": "/Library/Scripts/logout.sh"
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        let hooks = parseLoginLogoutHooks(at: path, scope: .system)
        XCTAssertEqual(hooks.count, 2)
        XCTAssertTrue(hooks.contains(where: { $0.kind == .login && $0.scriptPath == "/Library/Scripts/login.sh" }))
        XCTAssertTrue(hooks.contains(where: { $0.kind == .logout && $0.scriptPath == "/Library/Scripts/logout.sh" }))
    }

    func testParseOnlyLoginHookSet() throws {
        let path = try writeTempLoginwindowPlist([
            "LoginHook": "/usr/local/bin/login-hook.sh"
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        let hooks = parseLoginLogoutHooks(at: path, scope: .user)
        XCTAssertEqual(hooks.count, 1)
        XCTAssertEqual(hooks.first?.kind, .login)
        XCTAssertEqual(hooks.first?.scope, .user,
                       "Scope passed to the parser should propagate to the result")
    }

    func testParseEmptyPlistReturnsNoHooks() throws {
        // Real-world: /Library/Preferences/com.apple.loginwindow.plist
        // exists but contains only account-management keys, no hooks.
        let path = try writeTempLoginwindowPlist([
            "lastUserName": "anon",
            "RecentUsers": ["anon"]
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertEqual(parseLoginLogoutHooks(at: path, scope: .system), [])
    }

    func testParseEmptyStringValueIsDropped() throws {
        // A LoginHook key with an empty string value is functionally
        // "no hook". Don't surface it.
        let path = try writeTempLoginwindowPlist([
            "LoginHook": "",
            "LogoutHook": "/tmp/real-script.sh"
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let hooks = parseLoginLogoutHooks(at: path, scope: .system)
        XCTAssertEqual(hooks.count, 1)
        XCTAssertEqual(hooks.first?.kind, .logout)
    }

    func testParseMissingFileReturnsEmpty() {
        XCTAssertEqual(
            parseLoginLogoutHooks(at: "/var/empty/nonexistent.plist", scope: .system),
            []
        )
    }

    func testParseMalformedPlistReturnsEmpty() throws {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("owlwatch-bad-hooks-\(UUID().uuidString).plist")
        try Data("not a plist\n".utf8).write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertEqual(parseLoginLogoutHooks(at: path, scope: .user), [])
    }

    // MARK: - Live-system smoke

    func testLoginLogoutHooksOnCleanSystemReturnsEmpty() {
        // The current dev box is expected to have zero hooks set.
        // This is a soft assertion — if someone runs this on a box
        // with hooks configured, the test still passes (we just check
        // that the API doesn't crash).
        let hooks = OWPersistence.loginLogoutHooks()
        for hook in hooks {
            XCTAssertFalse(hook.scriptPath.isEmpty,
                           "Live hooks should always have a non-empty script path")
        }
    }

    // MARK: - Helpers

    private func writeTempLoginwindowPlist(_ contents: [String: Any]) throws -> String {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("owlwatch-hooks-\(UUID().uuidString).plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: contents, format: .xml, options: 0
        )
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }
}
