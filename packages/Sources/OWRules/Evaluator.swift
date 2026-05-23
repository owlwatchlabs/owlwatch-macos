import Foundation
import OWPersistence
import OWProcess

/// Runs a set of rules against snapshot data and emits findings.
///
/// The evaluator is **snapshot-based**: it takes one frozen reading
/// of each data source and walks every rule × item pair. Streaming
/// evaluation (rules over live event streams) is M13.5+.
enum Evaluator {
    /// Evaluate `rules` against the supplied snapshots. Returns a
    /// report covering every match in evaluation order (rule load
    /// order × source iteration order).
    static func evaluate(rules: [Rule], snapshot: Snapshot) -> ScanReport {
        let started = Date()
        var findings: [Finding] = []
        var itemCount = 0

        for source in RuleSource.allCases {
            let sourceRules = rules.filter { $0.source == source }
            guard !sourceRules.isEmpty else { continue }

            switch source {
            case .process:
                itemCount += snapshot.processes.count
                for process in snapshot.processes {
                    for rule in sourceRules where matches(rule: rule, process: process) {
                        findings.append(makeFinding(
                            rule: rule,
                            targetID: "pid:\(process.pid)",
                            evidence: collectEvidence(rule: rule, process: process),
                            scannedAt: started
                        ))
                    }
                }
            case .launchService:
                itemCount += snapshot.launchServices.count
                for service in snapshot.launchServices {
                    for rule in sourceRules where matches(rule: rule, service: service) {
                        findings.append(makeFinding(
                            rule: rule,
                            targetID: service.plistPath,
                            evidence: collectEvidence(rule: rule, service: service),
                            scannedAt: started
                        ))
                    }
                }
            case .loginItem:
                itemCount += snapshot.loginItems.count
                for item in snapshot.loginItems {
                    for rule in sourceRules where matches(rule: rule, item: item) {
                        findings.append(makeFinding(
                            rule: rule,
                            targetID: item.uuid,
                            evidence: collectEvidence(rule: rule, item: item),
                            scannedAt: started
                        ))
                    }
                }
            case .binary:
                itemCount += snapshot.binaries.count
                for summary in snapshot.binaries {
                    for rule in sourceRules where matches(rule: rule, summary: summary) {
                        findings.append(makeFinding(
                            rule: rule,
                            targetID: summary.path,
                            evidence: collectEvidence(rule: rule, summary: summary),
                            scannedAt: started
                        ))
                    }
                }
            }
        }

        return ScanReport(
            findings: findings,
            rulesEvaluated: rules.count,
            itemsEvaluated: itemCount,
            scannedAt: started,
            elapsed: Date().timeIntervalSince(started)
        )
    }

    // MARK: - Per-source matchers

    private static func matches(rule: Rule, process: RunningProcess) -> Bool {
        for (field, predicate) in rule.match {
            let value = FieldExtractor.extract(field, from: process)
            guard predicate.evaluate(against: value) else { return false }
        }
        return true
    }

    private static func matches(rule: Rule, service: LaunchService) -> Bool {
        for (field, predicate) in rule.match {
            let value = FieldExtractor.extract(field, from: service)
            guard predicate.evaluate(against: value) else { return false }
        }
        return true
    }

    private static func matches(rule: Rule, item: LoginItem) -> Bool {
        for (field, predicate) in rule.match {
            let value = FieldExtractor.extract(field, from: item)
            guard predicate.evaluate(against: value) else { return false }
        }
        return true
    }

    private static func matches(rule: Rule, summary: BinarySummary) -> Bool {
        for (field, predicate) in rule.match {
            let value = FieldExtractor.extract(field, from: summary)
            guard predicate.evaluate(against: value) else { return false }
        }
        return true
    }

    // MARK: - Evidence

    private static func collectEvidence(rule: Rule, process: RunningProcess) -> [String: String] {
        var evidence: [String: String] = [:]
        for field in rule.evidence {
            evidence[field] = FieldExtractor.extract(field, from: process).asString ?? "(missing)"
        }
        return evidence
    }

    private static func collectEvidence(rule: Rule, service: LaunchService) -> [String: String] {
        var evidence: [String: String] = [:]
        for field in rule.evidence {
            evidence[field] = FieldExtractor.extract(field, from: service).asString ?? "(missing)"
        }
        return evidence
    }

    private static func collectEvidence(rule: Rule, item: LoginItem) -> [String: String] {
        var evidence: [String: String] = [:]
        for field in rule.evidence {
            evidence[field] = FieldExtractor.extract(field, from: item).asString ?? "(missing)"
        }
        return evidence
    }

    private static func collectEvidence(rule: Rule, summary: BinarySummary) -> [String: String] {
        var evidence: [String: String] = [:]
        for field in rule.evidence {
            evidence[field] = FieldExtractor.extract(field, from: summary).asString ?? "(missing)"
        }
        return evidence
    }

    private static func makeFinding(
        rule: Rule,
        targetID: String,
        evidence: [String: String],
        scannedAt: Date
    ) -> Finding {
        Finding(
            ruleID: rule.id,
            ruleName: rule.name,
            mitre: rule.mitre,
            severity: rule.severity,
            source: rule.source,
            targetID: targetID,
            evidence: evidence,
            scannedAt: scannedAt
        )
    }
}

/// Frozen reading of every data source the evaluator can consume.
/// Constructed by ``OWRules/captureSnapshot()`` for a live scan or
/// composed manually in tests.
public struct Snapshot: Sendable {
    public let processes: [RunningProcess]
    public let launchServices: [LaunchService]
    public let loginItems: [LoginItem]
    public let binaries: [BinarySummary]

    public init(
        processes: [RunningProcess] = [],
        launchServices: [LaunchService] = [],
        loginItems: [LoginItem] = [],
        binaries: [BinarySummary] = []
    ) {
        self.processes = processes
        self.launchServices = launchServices
        self.loginItems = loginItems
        self.binaries = binaries
    }
}
