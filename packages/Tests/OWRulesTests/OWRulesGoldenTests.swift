import Foundation
import OWNetwork
import OWPersistence
import OWProcess
@testable import OWRules
import XCTest

/// Golden regression suite for the **shipped rule library** under
/// `packages/Rules/`.
///
/// Two halves:
///
/// - ``testCleanSnapshotProducesNoFindings`` — a benign-looking
///   snapshot (Apple binaries in /System, no third-party kexts, no
///   wildcard listeners, no /tmp processes) must produce zero
///   findings across the whole library. Catches accidentally-broad
///   rules that fire on legitimate system state.
///
/// - Per-rule positive cases — for each shipped rule, a snapshot
///   tailored to fire **that** rule. Asserts ≥ 1 finding with the
///   expected target. Catches regressions where a rule's predicates
///   silently stop matching the case they're meant to catch.
///
/// Together: any change to the engine, predicate set, or rule
/// library that breaks the documented behavior surfaces here.
final class OWRulesGoldenTests: XCTestCase {
    /// Cached shipped-rule library.
    private static let shippedRules: [Rule] = {
        let url = shippedRulesURL()
        return (try? OWRules.loadRules(from: url)) ?? []
    }()

    private func rule(_ id: String) throws -> Rule {
        guard let match = Self.shippedRules.first(where: { $0.id == id }) else {
            XCTFail("shipped rule '\(id)' not found — was it renamed or removed?")
            throw OWRulesError.duplicateRuleID(id: id, urls: [])
        }
        return match
    }

    // MARK: - Negative baseline

    func testCleanSnapshotProducesNoFindings() {
        let snapshot = Snapshot(
            processes: [
                .init(pid: 1, parentPid: 0, name: "launchd",
                      path: "/sbin/launchd", userId: 0),
                .init(pid: 100, parentPid: 1, name: "Finder",
                      path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder",
                      userId: 501)
            ],
            launchServices: [
                .init(plistPath: "/System/Library/LaunchDaemons/com.apple.kextd.plist",
                      scope: .platformDaemon, label: "com.apple.kextd",
                      executablePath: "/usr/libexec/kextd",
                      arguments: [], runAtLoad: true, keepAlive: .always(true),
                      watchPaths: [], startInterval: nil,
                      startCalendarInterval: [], isDisabled: false)
            ],
            loginItems: [
                .init(uuid: "ABCD", userId: 501, name: "Trusted",
                      developerName: "Apple", teamIdentifier: nil,
                      bundleIdentifier: "com.apple.trusted",
                      parentIdentifier: nil, identifier: "trusted",
                      url: nil, kind: .app, kindRawValue: 0x2,
                      disposition: .enabled)
            ],
            binaries: [
                BinarySummary(
                    path: "/usr/bin/ls", isUniversal: false, sliceCount: 1,
                    architectures: ["arm64"],
                    linkedDylibs: ["/usr/lib/libSystem.B.dylib"],
                    rpaths: [], hasRWXSegment: false, maxSectionEntropy: 5.8
                )
            ],
            connections: [
                .init(pid: 100, fd: 3, family: .ipv4, protocol: .tcp,
                      localAddress: "127.0.0.1", localPort: 50000,
                      remoteAddress: nil, remotePort: nil,
                      tcpState: .listen)
            ],
            kernelExtensions: [
                .init(bundlePath: "/System/Library/Extensions/AppleHIDKeyboard.kext",
                      bundleIdentifier: "com.apple.driver.AppleHIDKeyboard",
                      shortVersion: "1.0", bundleVersion: "1",
                      executableName: nil, executablePath: nil,
                      scope: .platform)
            ],
            signatures: [
                SignatureSummary(
                    path: "/usr/bin/ls", isSigned: true, isValid: true,
                    signatureType: "apple", identifier: "com.apple.ls",
                    teamIdentifier: nil, cdHashHex: "abc",
                    authoritiesJoined: "Software Signing",
                    flagsSymbolic: "runtime",
                    hasHardenedRuntime: true, hardenedRuntimeVersion: "14.0.0",
                    isStapledForNotarization: false, entitlementsCount: 0
                )
            ]
        )
        let report = OWRules.scan(rules: Self.shippedRules, snapshot: snapshot)
        XCTAssertTrue(
            report.findings.isEmpty,
            "shipped rules fired on clean baseline snapshot: "
                + report.findings.map { "\($0.ruleID)@\($0.targetID)" }.joined(separator: ", ")
        )
    }

    // MARK: - Per-rule positive cases

    func testT1546LaunchAgentInDownloads() throws {
        let snapshot = Snapshot(launchServices: [
            .init(plistPath: "/Users/anon/Downloads/com.evil.plist",
                  scope: .userAgent, label: "com.evil",
                  executablePath: "/Users/anon/Downloads/payload",
                  arguments: [], runAtLoad: true, keepAlive: .always(false),
                  watchPaths: [], startInterval: nil,
                  startCalendarInterval: [], isDisabled: false)
        ])
        let report = OWRules.scan(
            rules: [try rule("T1546.004-launchagent-in-downloads")],
            snapshot: snapshot
        )
        XCTAssertEqual(report.findings.count, 1)
        XCTAssertEqual(report.findings[0].targetID, "/Users/anon/Downloads/com.evil.plist")
    }

    func testT1546LaunchAgentInTmp() throws {
        let snapshot = Snapshot(launchServices: [
            .init(plistPath: "/Library/LaunchDaemons/com.evil.plist",
                  scope: .systemDaemon, label: "com.evil",
                  executablePath: "/tmp/payload",
                  arguments: [], runAtLoad: true, keepAlive: .always(false),
                  watchPaths: [], startInterval: nil,
                  startCalendarInterval: [], isDisabled: false)
        ])
        let report = OWRules.scan(
            rules: [try rule("T1546.004-launchagent-in-tmp")],
            snapshot: snapshot
        )
        XCTAssertEqual(report.findings.count, 1)
        XCTAssertEqual(report.findings[0].severity, Severity.critical)
    }

    func testT1059ProcessFromTmp() throws {
        let snapshot = Snapshot(processes: [
            .init(pid: 9999, parentPid: 1, name: "payload",
                  path: "/tmp/payload", userId: 501, arguments: [])
        ])
        let report = OWRules.scan(
            rules: [try rule("T1059.004-process-from-tmp")],
            snapshot: snapshot
        )
        XCTAssertEqual(report.findings.count, 1)
        XCTAssertEqual(report.findings[0].targetID, "pid:9999")
    }

    func testT1059ProcessFromTmpIgnoresAppleHelpers() throws {
        // Apple's own short-lived helpers under /tmp/com.apple.* are
        // explicitly excluded — the negative-lookahead in the regex
        // is the entire reason it ships.
        let snapshot = Snapshot(processes: [
            .init(pid: 100, parentPid: 1, name: "helper",
                  path: "/tmp/com.apple.helper", userId: 501, arguments: [])
        ])
        let report = OWRules.scan(
            rules: [try rule("T1059.004-process-from-tmp")],
            snapshot: snapshot
        )
        XCTAssertTrue(report.findings.isEmpty,
                      "rule must not fire on Apple's own /tmp/com.apple.* helpers")
    }

    func testT1547LoginItemNoDeveloper() throws {
        let snapshot = Snapshot(loginItems: [
            .init(uuid: "AAAA", userId: 501, name: "evil",
                  developerName: nil, teamIdentifier: nil,
                  bundleIdentifier: nil, parentIdentifier: nil,
                  identifier: "evil", url: "/tmp/evil",
                  kind: .legacyAgent, kindRawValue: 0,
                  disposition: .enabled)
        ])
        let report = OWRules.scan(
            rules: [try rule("T1547.001-login-item-no-developer")],
            snapshot: snapshot
        )
        XCTAssertEqual(report.findings.count, 1)
        XCTAssertEqual(report.findings[0].targetID, "AAAA")
    }

    func testT1059CurlPipeShell() throws {
        let snapshot = Snapshot(processes: [
            .init(pid: 7, parentPid: 1, name: "bash",
                  path: "/bin/bash", userId: 501,
                  arguments: ["bash", "-c", "curl https://example.com/install.sh | bash"])
        ])
        let report = OWRules.scan(
            rules: [try rule("T1059.004-curl-pipe-shell")],
            snapshot: snapshot
        )
        XCTAssertEqual(report.findings.count, 1)
    }

    func testT1027HighEntropySection() throws {
        let snapshot = Snapshot(binaries: [
            BinarySummary(
                path: "/Users/anon/Downloads/packer", isUniversal: false,
                sliceCount: 1, architectures: ["arm64"],
                linkedDylibs: [], rpaths: [],
                hasRWXSegment: false, maxSectionEntropy: 7.91
            )
        ])
        let report = OWRules.scan(
            rules: [try rule("T1027.002-high-entropy-section")],
            snapshot: snapshot
        )
        XCTAssertEqual(report.findings.count, 1)
    }

    func testT1027HighEntropyExcludedFromSystem() throws {
        // The shipped rule excludes /System/ paths to avoid firing
        // on Apple binaries that legitimately embed compressed assets
        // (bookassetd, commerce, BKAgentService).
        let snapshot = Snapshot(binaries: [
            BinarySummary(
                path: "/System/Library/PrivateFrameworks/Foo/bar",
                isUniversal: false, sliceCount: 1, architectures: ["arm64"],
                linkedDylibs: [], rpaths: [],
                hasRWXSegment: false, maxSectionEntropy: 7.91
            )
        ])
        let report = OWRules.scan(
            rules: [try rule("T1027.002-high-entropy-section")],
            snapshot: snapshot
        )
        XCTAssertTrue(report.findings.isEmpty)
    }

    func testT1574RWXSegment() throws {
        let snapshot = Snapshot(binaries: [
            BinarySummary(
                path: "/Users/anon/build/jit-app", isUniversal: false,
                sliceCount: 1, architectures: ["arm64"],
                linkedDylibs: [], rpaths: [],
                hasRWXSegment: true, maxSectionEntropy: 6.0
            )
        ])
        let report = OWRules.scan(
            rules: [try rule("T1574.006-rwx-segment")],
            snapshot: snapshot
        )
        XCTAssertEqual(report.findings.count, 1)
    }

    func testT1564ProcessInHiddenDir() throws {
        let snapshot = Snapshot(processes: [
            .init(pid: 42, parentPid: 1, name: "stash",
                  path: "/Users/anon/.hidden/stash", userId: 501)
        ])
        let report = OWRules.scan(
            rules: [try rule("T1564.001-process-in-hidden-dir")],
            snapshot: snapshot
        )
        XCTAssertEqual(report.findings.count, 1)
    }

    func testT1036AppleBinaryMasquerade() throws {
        let snapshot = Snapshot(processes: [
            .init(pid: 13, parentPid: 1, name: "launchd",
                  path: "/Users/anon/Downloads/launchd", userId: 501)
        ])
        let report = OWRules.scan(
            rules: [try rule("T1036.005-apple-binary-masquerade")],
            snapshot: snapshot
        )
        XCTAssertEqual(report.findings.count, 1)
    }

    func testT1543ThirdPartyLaunchDaemon() throws {
        let snapshot = Snapshot(launchServices: [
            .init(plistPath: "/Library/LaunchDaemons/com.docker.plist",
                  scope: .systemDaemon, label: "com.docker",
                  executablePath: "/usr/local/bin/com.docker.vmnetd",
                  arguments: [], runAtLoad: true, keepAlive: .always(true),
                  watchPaths: [], startInterval: nil,
                  startCalendarInterval: [], isDisabled: false)
        ])
        let report = OWRules.scan(
            rules: [try rule("T1543.001-third-party-launch-daemon")],
            snapshot: snapshot
        )
        XCTAssertEqual(report.findings.count, 1)
    }

    func testT1547LaunchServiceNoExecutable() throws {
        let snapshot = Snapshot(launchServices: [
            .init(plistPath: "/Library/LaunchAgents/com.weird.plist",
                  scope: .systemAgent, label: "com.weird",
                  executablePath: nil,
                  arguments: [], runAtLoad: false, keepAlive: .always(false),
                  watchPaths: [], startInterval: nil,
                  startCalendarInterval: [], isDisabled: false)
        ])
        let report = OWRules.scan(
            rules: [try rule("T1547.011-launch-service-no-executable")],
            snapshot: snapshot
        )
        XCTAssertEqual(report.findings.count, 1)
    }

    func testT1071ListenerOnAllInterfaces() throws {
        let snapshot = Snapshot(connections: [
            .init(pid: 10, fd: 5, family: .ipv4, protocol: .tcp,
                  localAddress: "0.0.0.0", localPort: 1337,
                  remoteAddress: nil, remotePort: nil, tcpState: .listen)
        ])
        let report = OWRules.scan(
            rules: [try rule("T1071-listener-on-all-interfaces")],
            snapshot: snapshot
        )
        XCTAssertEqual(report.findings.count, 1)
    }

    func testT1547ThirdPartyKernelExtension() throws {
        let snapshot = Snapshot(kernelExtensions: [
            .init(bundlePath: "/Library/Extensions/HighPointIOP.kext",
                  bundleIdentifier: "com.highpoint-tech.kext.HighPointIOP",
                  shortVersion: "4.4.5", bundleVersion: "1",
                  executableName: "HighPointIOP", executablePath: nil,
                  scope: .system)
        ])
        let report = OWRules.scan(
            rules: [try rule("T1547.006-third-party-kernel-extension")],
            snapshot: snapshot
        )
        XCTAssertEqual(report.findings.count, 1)
    }

    func testT1553UnsignedExecutable() throws {
        let snapshot = Snapshot(signatures: [
            SignatureSummary(
                path: "/Users/anon/Downloads/payload",
                isSigned: false, isValid: false,
                signatureType: "unsigned", identifier: nil,
                teamIdentifier: nil, cdHashHex: nil,
                authoritiesJoined: "", flagsSymbolic: "",
                hasHardenedRuntime: false, hardenedRuntimeVersion: nil,
                isStapledForNotarization: false, entitlementsCount: 0
            )
        ])
        let report = OWRules.scan(
            rules: [try rule("T1553.002-unsigned-executable")],
            snapshot: snapshot
        )
        XCTAssertEqual(report.findings.count, 1)
    }

    func testT1553DeveloperIDWithoutStapledTicket() throws {
        let snapshot = Snapshot(signatures: [
            SignatureSummary(
                path: "/Applications/VSCode.app/Contents/MacOS/Electron",
                isSigned: true, isValid: true,
                signatureType: "developer_id", identifier: "com.microsoft.VSCode",
                teamIdentifier: "UBF8T346G9", cdHashHex: "deadbeef",
                authoritiesJoined: "Developer ID Application: Microsoft Corp",
                flagsSymbolic: "runtime",
                hasHardenedRuntime: true, hardenedRuntimeVersion: "14.0.0",
                isStapledForNotarization: false, entitlementsCount: 0
            )
        ])
        let report = OWRules.scan(
            rules: [try rule("T1553.005-developer-id-without-stapled-ticket")],
            snapshot: snapshot
        )
        XCTAssertEqual(report.findings.count, 1)
    }

    func testT1553DeveloperIDWithoutHardenedRuntime() throws {
        let snapshot = Snapshot(signatures: [
            SignatureSummary(
                path: "/Applications/LegacyApp.app/Contents/MacOS/LegacyApp",
                isSigned: true, isValid: true,
                signatureType: "developer_id", identifier: "com.legacy.app",
                teamIdentifier: "ABCDE12345", cdHashHex: "cafef00d",
                authoritiesJoined: "Developer ID Application: Legacy",
                flagsSymbolic: "",
                hasHardenedRuntime: false, hardenedRuntimeVersion: nil,
                isStapledForNotarization: false, entitlementsCount: 0
            )
        ])
        let report = OWRules.scan(
            rules: [try rule("T1553.005-developer-id-without-hardened-runtime")],
            snapshot: snapshot
        )
        XCTAssertEqual(report.findings.count, 1)
    }

    func testT1027AdhocSignedOutsideSystem() throws {
        let snapshot = Snapshot(signatures: [
            SignatureSummary(
                path: "/Users/anon/build/debug/myapp",
                isSigned: true, isValid: true,
                signatureType: "adhoc", identifier: "myapp",
                teamIdentifier: nil, cdHashHex: "1234",
                authoritiesJoined: "", flagsSymbolic: "adhoc",
                hasHardenedRuntime: false, hardenedRuntimeVersion: nil,
                isStapledForNotarization: false, entitlementsCount: 0
            )
        ])
        let report = OWRules.scan(
            rules: [try rule("T1027-adhoc-signed-outside-system")],
            snapshot: snapshot
        )
        XCTAssertEqual(report.findings.count, 1)
    }
}

/// Resolves the path to the shipped rule library from the test
/// bundle. SPM tests run from `.build/<config>/`; the library lives
/// at `<repo>/packages/Rules/`.
private func shippedRulesURL() -> URL {
    let thisFile = URL(fileURLWithPath: #filePath)
    return thisFile
        .deletingLastPathComponent()  // OWRulesTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // packages
        .appendingPathComponent("Rules", isDirectory: true)
}
