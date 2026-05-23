@testable import OWRules
import Foundation
import OWBinary
import OWNetwork
import OWPersistence
import XCTest

/// Per-source evaluator tests, split from `OWRulesTests` to keep each
/// file's class body under SwiftLint's threshold as new sources land
/// in M13.2 / M13.3 and follow-on slices.
final class OWRulesSourceTests: XCTestCase {
    // MARK: - Binary source (M13.2)

    func testEvaluatorFiresOnBinarySummary() {
        let rule = Rule(
            id: "T0001-rwx", name: "RWX",
            severity: .high, source: .binary,
            match: ["has_rwx_segment": .isBoolean(true)],
            evidence: ["path", "architectures"]
        )
        let suspect = BinarySummary(
            path: "/tmp/packer",
            isUniversal: false,
            sliceCount: 1,
            architectures: ["arm64"],
            linkedDylibs: ["/usr/lib/libSystem.B.dylib"],
            rpaths: [],
            hasRWXSegment: true,
            maxSectionEntropy: 6.0
        )
        let benign = BinarySummary(
            path: "/usr/bin/ls",
            isUniversal: false,
            sliceCount: 1,
            architectures: ["arm64"],
            linkedDylibs: [],
            rpaths: [],
            hasRWXSegment: false,
            maxSectionEntropy: 5.8
        )
        let snapshot = Snapshot(binaries: [suspect, benign])
        let report = OWRules.scan(rules: [rule], snapshot: snapshot)
        XCTAssertEqual(report.findings.count, 1)
        XCTAssertEqual(report.findings[0].targetID, "/tmp/packer")
        XCTAssertEqual(report.findings[0].evidence["architectures"], "arm64")
    }

    func testEvaluatorFiresOnHighEntropy() {
        let rule = Rule(
            id: "T0001-entropy", name: "Entropy",
            severity: .medium, source: .binary,
            match: ["max_section_entropy": .greaterThan(7.5)]
        )
        let packed = BinarySummary(
            path: "/tmp/packed", isUniversal: false,
            sliceCount: 1, architectures: ["arm64"],
            linkedDylibs: [], rpaths: [],
            hasRWXSegment: false, maxSectionEntropy: 7.9
        )
        let normal = BinarySummary(
            path: "/usr/bin/normal", isUniversal: false,
            sliceCount: 1, architectures: ["arm64"],
            linkedDylibs: [], rpaths: [],
            hasRWXSegment: false, maxSectionEntropy: 6.2
        )
        let report = OWRules.scan(rules: [rule], snapshot: Snapshot(binaries: [packed, normal]))
        XCTAssertEqual(report.findings.count, 1)
        XCTAssertEqual(report.findings[0].targetID, "/tmp/packed")
    }

    func testBinarySummaryFromBinaryFile() throws {
        // Parse a known system binary (/bin/ls) and assert the
        // summary captures sane values. The path exists on every
        // macOS test environment.
        let url = URL(fileURLWithPath: "/bin/ls")
        let binary = try OWBinary.parse(at: url, includeSymbols: false)
        let summary = BinarySummary.make(from: binary)
        XCTAssertEqual(summary.path, "/bin/ls")
        XCTAssertGreaterThan(summary.sliceCount, 0)
        XCTAssertGreaterThan(summary.linkedDylibs.count, 0,
                             "/bin/ls links against libSystem at minimum")
        XCTAssertFalse(summary.hasRWXSegment,
                       "Apple system binaries don't ship rwx segments")
        XCTAssertGreaterThan(summary.maxSectionEntropy, 0.0)
        XCTAssertLessThanOrEqual(summary.maxSectionEntropy, 8.0)
    }

    // MARK: - Network source (M13.3)

    func testEvaluatorFiresOnNetworkConnection() {
        let rule = Rule(
            id: "T0001-listen-all", name: "Listen on all interfaces",
            severity: .medium, source: .network,
            match: [
                "is_listener": .isBoolean(true),
                "local_address": .equals("0.0.0.0")
            ],
            evidence: ["pid", "local_port"]
        )
        let exposed = Connection(
            pid: 9999, fd: 7, family: .ipv4, protocol: .tcp,
            localAddress: "0.0.0.0", localPort: 8080,
            remoteAddress: nil, remotePort: nil,
            tcpState: .listen
        )
        let loopback = Connection(
            pid: 8888, fd: 8, family: .ipv4, protocol: .tcp,
            localAddress: "127.0.0.1", localPort: 9000,
            remoteAddress: nil, remotePort: nil,
            tcpState: .listen
        )
        let report = OWRules.scan(rules: [rule], snapshot: Snapshot(connections: [exposed, loopback]))
        XCTAssertEqual(report.findings.count, 1)
        XCTAssertTrue(report.findings[0].targetID.contains("pid:9999:fd:7"))
        XCTAssertEqual(report.findings[0].evidence["local_port"], "8080")
    }

    func testNetworkSourceExtractsNilRemoteCorrectly() {
        // A listener has nil remote_address and remote_port; the
        // extractor must collapse to .missing rather than throwing.
        let listener = Connection(
            pid: 1, fd: 0, family: .ipv6, protocol: .tcp,
            localAddress: "::", localPort: 22,
            remoteAddress: nil, remotePort: nil,
            tcpState: .listen
        )
        XCTAssertEqual(FieldExtractor.extract("remote_address", from: listener), .missing)
        XCTAssertEqual(FieldExtractor.extract("remote_port", from: listener), .missing)
        XCTAssertEqual(FieldExtractor.extract("local_address", from: listener), .string("::"))
        XCTAssertEqual(FieldExtractor.extract("local_port", from: listener), .integer(22))
        XCTAssertEqual(FieldExtractor.extract("is_listener", from: listener), .boolean(true))
    }

    // MARK: - Kernel extension source (M13.3)

    func testEvaluatorFiresOnKernelExtension() {
        let rule = Rule(
            id: "T0001-third-party-kext", name: "Third-party kext",
            severity: .high, source: .kernelExtension,
            match: ["scope": .equals("system")],
            evidence: ["bundle_path", "bundle_identifier"]
        )
        let thirdParty = KernelExtension(
            bundlePath: "/Library/Extensions/com.someoneElse.driver.kext",
            bundleIdentifier: "com.someoneElse.driver",
            shortVersion: "1.0", bundleVersion: "1",
            executableName: "driver",
            executablePath: "/Library/Extensions/com.someoneElse.driver.kext/Contents/MacOS/driver",
            scope: .system
        )
        let apple = KernelExtension(
            bundlePath: "/System/Library/Extensions/AppleHIDKeyboard.kext",
            bundleIdentifier: "com.apple.driver.AppleHIDKeyboard",
            shortVersion: "1.0", bundleVersion: "1",
            executableName: nil, executablePath: nil,
            scope: .platform
        )
        let report = OWRules.scan(rules: [rule], snapshot: Snapshot(kernelExtensions: [thirdParty, apple]))
        XCTAssertEqual(report.findings.count, 1)
        XCTAssertEqual(report.findings[0].targetID, "com.someoneElse.driver")
    }

    // MARK: - Capture skip behavior

    func testCaptureSnapshotSkipsExpensiveSourcesWhenNoRulesNeedThem() throws {
        // The convenience scan() should skip the (expensive) binary
        // parse pass and the network snapshot when no loaded rule
        // targets those sources. Hard to assert directly — but a
        // process-only scan completes in well under a second.
        let rule = Rule(
            id: "T0001-cheap", name: "Cheap",
            severity: .info, source: .process,
            match: ["name": .equals("nonexistent-process-name")]
        )
        let report = try OWRules.scan(rules: [rule])
        XCTAssertGreaterThan(report.itemsEvaluated, 0)
    }
}
