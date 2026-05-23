import CoreServices
import Foundation
@testable import OWPersistence
import XCTest

final class PersistenceMonitorTests: XCTestCase {
    // MARK: - classifyKind

    func testClassifyKindFavorsRemovedOverModified() {
        // FSEvents often sets both Removed and Modified flags in the
        // same callback when a file is unlinked. We want the
        // higher-priority kind (removed) to win.
        let flags = FSEventStreamEventFlags(
            UInt32(kFSEventStreamEventFlagItemRemoved)
                | UInt32(kFSEventStreamEventFlagItemModified)
        )
        XCTAssertEqual(classifyKind(flags: flags), .removed)
    }

    func testClassifyKindRecognizesCreated() {
        let flags = FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)
        XCTAssertEqual(classifyKind(flags: flags), .added)
    }

    func testClassifyKindRecognizesRenamed() {
        let flags = FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)
        XCTAssertEqual(classifyKind(flags: flags), .renamed)
    }

    func testClassifyKindRecognizesXattrMod() {
        // The Gatekeeper-bypass signature: someone stripping
        // com.apple.quarantine fires this flag.
        let flags = FSEventStreamEventFlags(kFSEventStreamEventFlagItemXattrMod)
        XCTAssertEqual(classifyKind(flags: flags), .xattrChanged)
    }

    func testClassifyKindRecognizesInodeMetaMod() {
        let flags = FSEventStreamEventFlags(kFSEventStreamEventFlagItemInodeMetaMod)
        XCTAssertEqual(classifyKind(flags: flags), .metadataChanged)
    }

    func testClassifyKindFallsBackToModifiedForUnknown() {
        // An event with no recognized item-level flag should land in
        // .modified as a safe default. Real FSEvents emits this when
        // a directory-summary event fires (without file-level flags).
        let flags = FSEventStreamEventFlags(0)
        XCTAssertEqual(classifyKind(flags: flags), .modified)
    }

    // MARK: - classifyScope

    func testClassifyScopeForPlatformLaunchdPaths() {
        XCTAssertEqual(
            classifyScope(path: "/System/Library/LaunchDaemons/com.apple.foo.plist"),
            .platformLaunchd
        )
        XCTAssertEqual(
            classifyScope(path: "/System/Library/LaunchAgents/com.apple.bar.plist"),
            .platformLaunchd
        )
    }

    func testClassifyScopeForSystemLaunchdPaths() {
        XCTAssertEqual(
            classifyScope(path: "/Library/LaunchDaemons/com.example.foo.plist"),
            .systemLaunchd
        )
        XCTAssertEqual(
            classifyScope(path: "/Library/LaunchAgents/com.example.bar.plist"),
            .systemLaunchd
        )
    }

    func testClassifyScopeForUserLaunchdPaths() {
        XCTAssertEqual(
            classifyScope(path: "/Users/anon/Library/LaunchAgents/com.example.foo.plist"),
            .userLaunchd
        )
    }

    func testClassifyScopeForSystemExtensionsRegistry() {
        XCTAssertEqual(
            classifyScope(path: "/Library/SystemExtensions/db.plist"),
            .systemExtensionsRegistry
        )
    }

    func testClassifyScopeForKextDirectories() {
        XCTAssertEqual(
            classifyScope(path: "/System/Library/Extensions/IOKit.kext"),
            .kernelExtensions
        )
        XCTAssertEqual(
            classifyScope(path: "/Library/Extensions/HighPointIOP.kext"),
            .kernelExtensions
        )
    }

    func testClassifyScopeForLoginwindowPlists() {
        XCTAssertEqual(
            classifyScope(path: "/Library/Preferences/com.apple.loginwindow.plist"),
            .loginwindowPlist
        )
        XCTAssertEqual(
            classifyScope(path: "/Users/anon/Library/Preferences/com.apple.loginwindow.plist"),
            .loginwindowPlist
        )
    }

    func testClassifyScopeFallsBackToOther() {
        XCTAssertEqual(
            classifyScope(path: "/tmp/random.plist"),
            .other
        )
    }

    // MARK: - defaultMonitorPaths

    func testDefaultMonitorPathsCoversAllScopes() {
        let paths = OWPersistence.defaultMonitorPaths
        XCTAssertTrue(paths.contains("/System/Library/LaunchDaemons"))
        XCTAssertTrue(paths.contains("/Library/LaunchDaemons"))
        XCTAssertTrue(paths.contains("/Library/LaunchAgents"))
        XCTAssertTrue(paths.contains("/Library/SystemExtensions"))
        XCTAssertTrue(paths.contains("/Library/Extensions"))
        // User paths are home-relative; check by suffix.
        XCTAssertTrue(paths.contains(where: { $0.hasSuffix("/Library/LaunchAgents") && $0.hasPrefix("/Users/") }),
                      "User LaunchAgents path should be included")
        XCTAssertTrue(paths.contains(where: { $0.hasSuffix("com.apple.loginwindow.plist") && $0.hasPrefix("/Users/") }),
                      "User loginwindow plist should be included")
    }
}
