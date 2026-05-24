import Foundation
import OWPersistence
import OWProcess
@testable import OWRules
import XCTest

final class OWRulesTests: XCTestCase {
    // MARK: - Severity

    func testSeverityIsComparable() {
        XCTAssertLessThan(Severity.info, Severity.critical)
        XCTAssertLessThan(Severity.medium, Severity.high)
        XCTAssertEqual(Severity.high, Severity.high)
        XCTAssertEqual(Severity.allCases.count, 5)
    }

    // MARK: - Predicate evaluation

    func testEqualsPredicate() {
        let predicate = Predicate.equals("hello")
        XCTAssertTrue(predicate.evaluate(against: .string("hello")))
        XCTAssertFalse(predicate.evaluate(against: .string("Hello")))
        XCTAssertFalse(predicate.evaluate(against: .missing))
    }

    func testStartsWithPredicate() {
        let predicate = Predicate.startsWith("/tmp/")
        XCTAssertTrue(predicate.evaluate(against: .string("/tmp/abc")))
        XCTAssertFalse(predicate.evaluate(against: .string("/var/tmp/abc")))
        XCTAssertFalse(predicate.evaluate(against: .missing))
    }

    func testMatchesRegexPredicate() {
        let predicate = Predicate.matches("^T\\d{4}$")
        XCTAssertTrue(predicate.evaluate(against: .string("T1234")))
        XCTAssertFalse(predicate.evaluate(against: .string("T12")))
        XCTAssertFalse(predicate.evaluate(against: .string("t1234")))
    }

    func testInSetPredicate() {
        let predicate = Predicate.inSet(["sh", "bash", "zsh"])
        XCTAssertTrue(predicate.evaluate(against: .string("bash")))
        XCTAssertFalse(predicate.evaluate(against: .string("fish")))
    }

    func testExistsPredicate() {
        XCTAssertTrue(Predicate.exists(true).evaluate(against: .string("anything")))
        XCTAssertTrue(Predicate.exists(false).evaluate(against: .missing))
        XCTAssertFalse(Predicate.exists(true).evaluate(against: .missing))
        // Empty string-array collapses to .isPresent == false.
        XCTAssertFalse(Predicate.exists(true).evaluate(against: .stringArray([])))
        XCTAssertTrue(Predicate.exists(true).evaluate(against: .stringArray(["a"])))
    }

    func testIsBooleanPredicate() {
        XCTAssertTrue(Predicate.isBoolean(true).evaluate(against: .boolean(true)))
        XCTAssertFalse(Predicate.isBoolean(true).evaluate(against: .boolean(false)))
        XCTAssertFalse(Predicate.isBoolean(true).evaluate(against: .string("true")))
    }

    func testContainsOverArgumentsArray() {
        // Arguments arrays concatenate via space — `contains` against
        // an argv-style field matches across boundaries.
        let predicate = Predicate.contains("--no-verify")
        XCTAssertTrue(predicate.evaluate(against: .stringArray(["git", "commit", "--no-verify", "-m", "x"])))
        XCTAssertFalse(predicate.evaluate(against: .stringArray(["git", "commit", "-m", "x"])))
    }

    // MARK: - YAML loader

    func testLoadValidRule() throws {
        let yaml = """
        id: T1234-test
        name: Test rule
        severity: high
        when:
          source: process
          match:
            path:
              starts_with: /tmp/
        evidence:
          - pid
          - path
        """
        let rule = try loadRule(yaml: yaml)
        XCTAssertEqual(rule.id, "T1234-test")
        XCTAssertEqual(rule.severity, .high)
        XCTAssertEqual(rule.source, .process)
        XCTAssertEqual(rule.evidence, ["pid", "path"])
        XCTAssertEqual(rule.match["path"], .startsWith("/tmp/"))
    }

    func testLoadRuleWithScalarPredicateShorthand() throws {
        // A bare scalar predicate is shorthand for `equals: <value>`.
        let yaml = """
        id: T0001-shorthand
        name: Shorthand
        severity: low
        when:
          source: process
          match:
            name: bash
        """
        let rule = try loadRule(yaml: yaml)
        XCTAssertEqual(rule.match["name"], .equals("bash"))
    }

    func testLoadRuleRejectsUnknownField() {
        let yaml = """
        id: T0001-bad
        name: Bad
        severity: low
        when:
          source: process
          match:
            nonexistent_field:
              equals: x
        """
        XCTAssertThrowsError(try loadRule(yaml: yaml)) { error in
            guard case .unknownField(_, let source, let field) = error as? OWRulesError else {
                return XCTFail("expected .unknownField, got \(error)")
            }
            XCTAssertEqual(source, .process)
            XCTAssertEqual(field, "nonexistent_field")
        }
    }

    func testLoadRuleRejectsMissingSeverity() {
        let yaml = """
        id: T0001-bad
        name: Bad
        when:
          source: process
        """
        XCTAssertThrowsError(try loadRule(yaml: yaml)) { error in
            guard case .schemaViolation(_, let field, _) = error as? OWRulesError else {
                return XCTFail("expected .schemaViolation, got \(error)")
            }
            XCTAssertEqual(field, "severity")
        }
    }

    func testLoadRuleRejectsUnknownRootKey() {
        let yaml = """
        id: T0001-bad
        name: Bad
        severity: low
        when:
          source: process
        unknown_key: value
        """
        XCTAssertThrowsError(try loadRule(yaml: yaml)) { error in
            guard case .schemaViolation(_, let field, _) = error as? OWRulesError else {
                return XCTFail("expected .schemaViolation, got \(error)")
            }
            XCTAssertEqual(field, "unknown_key")
        }
    }

    func testLoadRuleRejectsUnknownWhenKey() {
        let yaml = """
        id: T0001-bad
        name: Bad
        severity: low
        when:
          source: process
          typo_match: {}
        """
        XCTAssertThrowsError(try loadRule(yaml: yaml)) { error in
            guard case .schemaViolation(_, let field, _) = error as? OWRulesError else {
                return XCTFail("expected .schemaViolation, got \(error)")
            }
            XCTAssertEqual(field, "when.typo_match")
        }
    }

    func testLoadRuleRejectsEmptyID() {
        let yaml = """
        id: ""
        name: Bad
        severity: low
        when:
          source: process
        """
        XCTAssertThrowsError(try loadRule(yaml: yaml)) { error in
            guard case .schemaViolation(_, let field, _) = error as? OWRulesError else {
                return XCTFail("expected .schemaViolation, got \(error)")
            }
            XCTAssertEqual(field, "id")
        }
    }

    func testLoadRuleRejectsInvalidIDCharacters() {
        let yaml = """
        id: T0001 with spaces
        name: Bad
        severity: low
        when:
          source: process
        """
        XCTAssertThrowsError(try loadRule(yaml: yaml)) { error in
            guard case .schemaViolation(_, let field, _) = error as? OWRulesError else {
                return XCTFail("expected .schemaViolation, got \(error)")
            }
            XCTAssertEqual(field, "id")
        }
    }

    func testLoadRuleRejectsMalformedMITRE() {
        let yaml = """
        id: T0001-bad
        name: Bad
        severity: low
        mitre: NOT-A-MITRE-ID
        when:
          source: process
        """
        XCTAssertThrowsError(try loadRule(yaml: yaml)) { error in
            guard case .schemaViolation(_, let field, _) = error as? OWRulesError else {
                return XCTFail("expected .schemaViolation, got \(error)")
            }
            XCTAssertEqual(field, "mitre")
        }
    }

    func testLoadRuleAcceptsValidMITRESubtechnique() throws {
        let yaml = """
        id: T1546.004-test
        name: Test
        severity: low
        mitre: T1546.004
        when:
          source: process
        """
        let rule = try loadRule(yaml: yaml)
        XCTAssertEqual(rule.mitre, "T1546.004")
    }

    func testLoadRuleRejectsDuplicateEvidenceFields() {
        let yaml = """
        id: T0001-dup-ev
        name: Dup evidence
        severity: low
        when:
          source: process
        evidence:
          - pid
          - name
          - pid
        """
        XCTAssertThrowsError(try loadRule(yaml: yaml)) { error in
            guard case .schemaViolation(_, let field, _) = error as? OWRulesError else {
                return XCTFail("expected .schemaViolation, got \(error)")
            }
            XCTAssertEqual(field, "evidence")
        }
    }

    func testLoadRuleRejectsInvalidRegex() {
        let yaml = """
        id: T0001-bad
        name: Bad
        severity: low
        when:
          source: process
          match:
            path:
              matches: '['
        """
        XCTAssertThrowsError(try loadRule(yaml: yaml))
    }

    func testLoadRulesFromDirectoryDetectsDuplicates() throws {
        let tmpDir = try createTempRulesDirectory(files: [
            "a.yml": validRuleYAML(id: "T0001-dup"),
            "b.yml": validRuleYAML(id: "T0001-dup")
        ])
        XCTAssertThrowsError(try OWRules.loadRules(from: tmpDir)) { error in
            guard case .duplicateRuleID(let id, _) = error as? OWRulesError else {
                return XCTFail("expected .duplicateRuleID, got \(error)")
            }
            XCTAssertEqual(id, "T0001-dup")
        }
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - Evaluator

    func testEvaluatorFiresOnMatchingProcess() {
        let rule = Rule(
            id: "T0001-tmp-proc", name: "Tmp proc",
            severity: .high, source: .process,
            match: ["path": .startsWith("/tmp/")],
            evidence: ["pid", "path"]
        )
        let process = RunningProcess(
            pid: 9999, parentPid: 1, name: "evil",
            path: "/tmp/evil", userId: 501, arguments: []
        )
        let snapshot = Snapshot(processes: [process])
        let report = OWRules.scan(rules: [rule], snapshot: snapshot)
        XCTAssertEqual(report.findings.count, 1)
        let finding = report.findings[0]
        XCTAssertEqual(finding.ruleID, "T0001-tmp-proc")
        XCTAssertEqual(finding.targetID, "pid:9999")
        XCTAssertEqual(finding.evidence["pid"], "9999")
        XCTAssertEqual(finding.evidence["path"], "/tmp/evil")
    }

    func testEvaluatorIgnoresNonMatchingItems() {
        let rule = Rule(
            id: "T0001-tmp-proc", name: "Tmp proc",
            severity: .high, source: .process,
            match: ["path": .startsWith("/tmp/")]
        )
        let process = RunningProcess(
            pid: 1, parentPid: 0, name: "launchd",
            path: "/sbin/launchd", userId: 0
        )
        let snapshot = Snapshot(processes: [process])
        let report = OWRules.scan(rules: [rule], snapshot: snapshot)
        XCTAssertTrue(report.findings.isEmpty)
        XCTAssertEqual(report.itemsEvaluated, 1)
        XCTAssertEqual(report.rulesEvaluated, 1)
    }

    func testEvaluatorANDsMultiplePredicates() {
        let rule = Rule(
            id: "T0001-and", name: "AND test",
            severity: .high, source: .process,
            match: [
                "path": .startsWith("/tmp/"),
                "name": .equals("payload")
            ]
        )
        let matching = RunningProcess(pid: 1, parentPid: 0, name: "payload", path: "/tmp/payload", userId: 501)
        let nameOnly = RunningProcess(pid: 2, parentPid: 0, name: "payload", path: "/usr/bin/payload", userId: 501)
        let pathOnly = RunningProcess(pid: 3, parentPid: 0, name: "other", path: "/tmp/other", userId: 501)
        let snapshot = Snapshot(processes: [matching, nameOnly, pathOnly])
        let report = OWRules.scan(rules: [rule], snapshot: snapshot)
        XCTAssertEqual(report.findings.count, 1)
        XCTAssertEqual(report.findings[0].targetID, "pid:1")
    }

    func testEvaluatorFiresOnLaunchService() {
        let rule = Rule(
            id: "T0001-launch", name: "Launch from /tmp",
            severity: .critical, source: .launchService,
            match: ["executable_path": .startsWith("/tmp/")],
            evidence: ["plist_path", "executable_path"]
        )
        let bad = LaunchService(
            plistPath: "/Library/LaunchDaemons/evil.plist",
            scope: .systemDaemon, label: "com.evil",
            executablePath: "/tmp/evil",
            arguments: [], runAtLoad: true, keepAlive: .always(false),
            watchPaths: [], startInterval: nil,
            startCalendarInterval: [], isDisabled: false
        )
        let report = OWRules.scan(rules: [rule], snapshot: Snapshot(launchServices: [bad]))
        XCTAssertEqual(report.findings.count, 1)
        XCTAssertEqual(report.findings[0].severity, Severity.critical)
        XCTAssertEqual(report.findings[0].evidence["executable_path"], "/tmp/evil")
    }

    func testEvaluatorFiresOnLoginItem() {
        let rule = Rule(
            id: "T0001-login", name: "Login no developer",
            severity: .medium, source: .loginItem,
            match: [
                "is_enabled": .isBoolean(true),
                "developer_name": .exists(false)
            ]
        )
        let suspect = LoginItem(
            uuid: "ABCD-1234", userId: 501, name: "thing",
            developerName: nil, teamIdentifier: nil,
            bundleIdentifier: nil, parentIdentifier: nil,
            identifier: "thing", url: "/tmp/thing",
            kind: .legacyAgent, kindRawValue: 0,
            disposition: .enabled
        )
        let legit = LoginItem(
            uuid: "EFGH-5678", userId: 501, name: "ok",
            developerName: "Apple",
            teamIdentifier: nil, bundleIdentifier: "com.apple.x",
            parentIdentifier: nil, identifier: "ok", url: nil,
            kind: .legacyAgent, kindRawValue: 0,
            disposition: .enabled
        )
        let report = OWRules.scan(rules: [rule], snapshot: Snapshot(loginItems: [suspect, legit]))
        XCTAssertEqual(report.findings.count, 1)
        XCTAssertEqual(report.findings[0].targetID, "ABCD-1234")
    }

    // MARK: - Shipped rule library smoke

    func testShippedRulesParseAndSchemaValidate() throws {
        // The library at packages/Rules/ must always load cleanly —
        // this is the regression gate for rule-format breakage.
        let url = shippedRulesURL()
        let rules = try OWRules.loadRules(from: url)
        XCTAssertGreaterThanOrEqual(rules.count, 17,
                                    "expected at least M13.1+M13.2+M13.3+M13.4 starter rules (5+4+4+4)")
        for rule in rules {
            XCTAssertFalse(rule.id.isEmpty, "rule \(rule.id) has empty id")
            XCTAssertFalse(rule.name.isEmpty, "rule \(rule.id) has empty name")
        }
    }

    // MARK: - Numeric predicates (M13.2)

    func testGreaterThanPredicate() {
        let predicate = Predicate.greaterThan(7.5)
        XCTAssertTrue(predicate.evaluate(against: .double(7.6)))
        XCTAssertTrue(predicate.evaluate(against: .integer(10)))
        XCTAssertFalse(predicate.evaluate(against: .double(7.5)))
        XCTAssertFalse(predicate.evaluate(against: .double(7.0)))
        XCTAssertFalse(predicate.evaluate(against: .string("8.0")))
        XCTAssertFalse(predicate.evaluate(against: .missing))
    }

    func testLessThanPredicate() {
        let predicate = Predicate.lessThan(100.0)
        XCTAssertTrue(predicate.evaluate(against: .double(50.0)))
        XCTAssertTrue(predicate.evaluate(against: .integer(99)))
        XCTAssertFalse(predicate.evaluate(against: .double(100.0)))
        XCTAssertFalse(predicate.evaluate(against: .double(150.0)))
        XCTAssertFalse(predicate.evaluate(against: .missing))
    }

    func testLoadRuleWithNumericPredicates() throws {
        let yaml = """
        id: T0001-numeric
        name: Numeric
        severity: medium
        when:
          source: binary
          match:
            max_section_entropy:
              greater_than: 7.5
        """
        let rule = try loadRule(yaml: yaml)
        XCTAssertEqual(rule.match["max_section_entropy"], .greaterThan(7.5))
    }

    func testLoadRuleNumericPredicateRejectsString() {
        let yaml = """
        id: T0001-bad-num
        name: Bad
        severity: low
        when:
          source: binary
          match:
            max_section_entropy:
              greater_than: "not-a-number"
        """
        XCTAssertThrowsError(try loadRule(yaml: yaml)) { error in
            guard case .schemaViolation = error as? OWRulesError else {
                return XCTFail("expected .schemaViolation, got \(error)")
            }
        }
    }

    // MARK: - Helpers

    private func loadRule(yaml: String) throws -> Rule {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("owrules-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let file = tmpDir.appendingPathComponent("rule.yml")
        try yaml.data(using: .utf8)!.write(to: file)
        return try OWRules.loadRule(from: file)
    }

    private func validRuleYAML(id: String) -> String {
        """
        id: \(id)
        name: Test
        severity: low
        when:
          source: process
          match:
            name: anything
        """
    }

    private func createTempRulesDirectory(files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("owrules-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, content) in files {
            try content.data(using: .utf8)!
                .write(to: dir.appendingPathComponent(name))
        }
        return dir
    }

    /// Walk up from the test bundle to find packages/Rules.
    /// SPM tests run from .build/<config>/, so packages/Rules lives a
    /// few levels up.
    private func shippedRulesURL() -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        // .../packages/Tests/OWRulesTests/OWRulesTests.swift
        //  → walk up to packages/, then into Rules.
        return thisFile
            .deletingLastPathComponent()  // OWRulesTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // packages
            .appendingPathComponent("Rules", isDirectory: true)
    }
}
