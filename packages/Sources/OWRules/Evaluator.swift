import Foundation
import OWNetwork
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
            evaluateSource(
                source, rules: sourceRules, snapshot: snapshot,
                startedAt: started, findings: &findings, itemCount: &itemCount
            )
        }

        return ScanReport(
            findings: findings,
            rulesEvaluated: rules.count,
            itemsEvaluated: itemCount,
            scannedAt: started,
            elapsed: Date().timeIntervalSince(started)
        )
    }

    /// Iterate the items for one data source and append every match.
    /// Split out of ``evaluate`` so the per-source switch's cyclomatic
    /// complexity doesn't blow past SwiftLint's threshold as new
    /// sources land.
    private static func evaluateSource(
        _ source: RuleSource,
        rules: [Rule],
        snapshot: Snapshot,
        startedAt: Date,
        findings: inout [Finding],
        itemCount: inout Int
    ) {
        switch source {
        case .process:
            itemCount += snapshot.processes.count
            for process in snapshot.processes {
                for rule in rules where matches(rule: rule, process: process) {
                    findings.append(makeFinding(
                        rule: rule, targetID: "pid:\(process.pid)",
                        evidence: collectEvidence(rule: rule, process: process),
                        scannedAt: startedAt
                    ))
                }
            }
        case .launchService:
            itemCount += snapshot.launchServices.count
            for service in snapshot.launchServices {
                for rule in rules where matches(rule: rule, service: service) {
                    findings.append(makeFinding(
                        rule: rule, targetID: service.plistPath,
                        evidence: collectEvidence(rule: rule, service: service),
                        scannedAt: startedAt
                    ))
                }
            }
        case .loginItem:
            itemCount += snapshot.loginItems.count
            for item in snapshot.loginItems {
                for rule in rules where matches(rule: rule, item: item) {
                    findings.append(makeFinding(
                        rule: rule, targetID: item.uuid,
                        evidence: collectEvidence(rule: rule, item: item),
                        scannedAt: startedAt
                    ))
                }
            }
        case .binary:
            itemCount += snapshot.binaries.count
            for summary in snapshot.binaries {
                for rule in rules where matches(rule: rule, summary: summary) {
                    findings.append(makeFinding(
                        rule: rule, targetID: summary.path,
                        evidence: collectEvidence(rule: rule, summary: summary),
                        scannedAt: startedAt
                    ))
                }
            }
        case .network:
            itemCount += snapshot.connections.count
            for connection in snapshot.connections {
                for rule in rules where matches(rule: rule, connection: connection) {
                    findings.append(makeFinding(
                        rule: rule, targetID: connectionID(connection),
                        evidence: collectEvidence(rule: rule, connection: connection),
                        scannedAt: startedAt
                    ))
                }
            }
        case .kernelExtension:
            itemCount += snapshot.kernelExtensions.count
            for kext in snapshot.kernelExtensions {
                for rule in rules where matches(rule: rule, kext: kext) {
                    findings.append(makeFinding(
                        rule: rule, targetID: kext.bundleIdentifier ?? kext.bundlePath,
                        evidence: collectEvidence(rule: rule, kext: kext),
                        scannedAt: startedAt
                    ))
                }
            }
        }
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

    private static func matches(rule: Rule, connection: Connection) -> Bool {
        for (field, predicate) in rule.match {
            let value = FieldExtractor.extract(field, from: connection)
            guard predicate.evaluate(against: value) else { return false }
        }
        return true
    }

    private static func matches(rule: Rule, kext: KernelExtension) -> Bool {
        for (field, predicate) in rule.match {
            let value = FieldExtractor.extract(field, from: kext)
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

    private static func collectEvidence(rule: Rule, connection: Connection) -> [String: String] {
        var evidence: [String: String] = [:]
        for field in rule.evidence {
            evidence[field] = FieldExtractor.extract(field, from: connection).asString ?? "(missing)"
        }
        return evidence
    }

    private static func collectEvidence(rule: Rule, kext: KernelExtension) -> [String: String] {
        var evidence: [String: String] = [:]
        for field in rule.evidence {
            evidence[field] = FieldExtractor.extract(field, from: kext).asString ?? "(missing)"
        }
        return evidence
    }

    /// Synthesizes a stable target ID for a connection. Connections
    /// don't have a natural unique key, so we compose pid + fd + the
    /// proto:local→remote tuple. Sockets get a unique (pid, fd) pair;
    /// the endpoint portion makes the ID self-describing in findings.
    private static func connectionID(_ connection: Connection) -> String {
        let proto = connection.protocol.rawValue
        let local = "\(connection.localAddress ?? "*"):\(connection.localPort.map(String.init) ?? "*")"
        let remote = "\(connection.remoteAddress ?? "*"):\(connection.remotePort.map(String.init) ?? "*")"
        return "pid:\(connection.pid):fd:\(connection.fd):\(proto):\(local)->\(remote)"
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
    public let connections: [Connection]
    public let kernelExtensions: [KernelExtension]

    public init(
        processes: [RunningProcess] = [],
        launchServices: [LaunchService] = [],
        loginItems: [LoginItem] = [],
        binaries: [BinarySummary] = [],
        connections: [Connection] = [],
        kernelExtensions: [KernelExtension] = []
    ) {
        self.processes = processes
        self.launchServices = launchServices
        self.loginItems = loginItems
        self.binaries = binaries
        self.connections = connections
        self.kernelExtensions = kernelExtensions
    }
}
