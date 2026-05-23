import ArgumentParser
import Foundation
import OWRules

struct ScanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Run Owlwatch's detection rules against the current system state.",
        discussion: """
            Loads YAML rules from <rules-dir>, captures a snapshot of the data \
            sources the rules reference (processes, launch services, login \
            items), evaluates every rule against every item, and prints any \
            findings.

            Exit code is 0 on a clean scan (no findings), 1 when at least one \
            finding fires, 2 on a rule-loading error. --severity caps the \
            output to findings at or above the supplied level (info <= low <= \
            medium <= high <= critical).

            --dry-run loads and schema-checks the rules but skips evaluation —
            useful for CI rule-format validation.

            Examples:
              owlwatch scan
              owlwatch scan --rules ./packages/Rules
              owlwatch scan --severity high
              owlwatch scan --rules ./packages/Rules --dry-run
              owlwatch scan --json > findings.json
            """
    )

    @Option(
        name: .long,
        help: "Directory containing YAML rule files (default: <repo>/packages/Rules from a checkout)."
    )
    var rules: String?

    @Option(name: .long, help: "Minimum severity to report. One of: info, low, medium, high, critical.")
    var severity: String = "info"

    @Flag(name: .long, help: "Parse and schema-check rules without evaluating them against the system.")
    var dryRun: Bool = false

    @Flag(name: .long, help: "Emit findings as JSON instead of the default text form.")
    var json: Bool = false

    func run() throws {
        let rulesURL = try resolveRulesDirectory()
        let loadedRules: [Rule]
        do {
            loadedRules = try OWRules.loadRules(from: rulesURL)
        } catch let error as OWRulesError {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            throw ExitCode(2)
        }

        guard let minimumSeverity = Severity(rawValue: severity) else {
            let message = "unknown severity '\(severity)' — must be one of: "
                + Severity.allCases.map { $0.rawValue }.joined(separator: ", ") + "\n"
            FileHandle.standardError.write(Data(message.utf8))
            throw ExitCode(2)
        }

        if dryRun {
            let line = "Loaded \(loadedRules.count) rule(s) from \(rulesURL.path) — schema OK.\n"
            FileHandle.standardOutput.write(Data(line.utf8))
            return
        }

        // Capture and evaluate as separate phases so the user can see
        // where wall-clock time went. Binary parsing (M13.2) can take
        // seconds on a busy system; the evaluator itself is sub-ms.
        let captureStart = Date()
        let needsBinaries = loadedRules.contains { $0.source == .binary }
        let needsNetwork = loadedRules.contains { $0.source == .network }
        let needsKexts = loadedRules.contains { $0.source == .kernelExtension }
        let needsArguments = loadedRules.contains { rule in
            rule.source == .process && (
                rule.match.keys.contains("arguments") || rule.evidence.contains("arguments")
            )
        }
        let snapshot = try OWRules.captureSnapshot(
            includeArguments: needsArguments,
            includeBinaries: needsBinaries,
            includeNetwork: needsNetwork,
            includeKernelExtensions: needsKexts
        )
        let captureElapsed = Date().timeIntervalSince(captureStart)

        let report = OWRules.scan(rules: loadedRules, snapshot: snapshot)
        let visible = report.findings.filter { $0.severity >= minimumSeverity }

        if json {
            try emitJSON(report: report, visible: visible, rulesURL: rulesURL,
                         captureElapsed: captureElapsed)
        } else {
            emitText(report: report, visible: visible, rulesURL: rulesURL,
                     minimumSeverity: minimumSeverity, captureElapsed: captureElapsed)
        }

        if !visible.isEmpty {
            throw ExitCode(1)
        }
    }

    // MARK: - Resolve rules directory

    /// Resolve the rules directory in this order:
    ///   1. --rules <path>
    ///   2. ./packages/Rules (so the command "just works" from a checkout)
    ///   3. $OWLWATCH_RULES env var
    /// Errors out if none exist.
    private func resolveRulesDirectory() throws -> URL {
        if let explicit = rules {
            return URL(fileURLWithPath: explicit)
        }
        let env = ProcessInfo.processInfo.environment
        if let envPath = env["OWLWATCH_RULES"], !envPath.isEmpty {
            return URL(fileURLWithPath: envPath)
        }
        let cwd = FileManager.default.currentDirectoryPath
        let local = URL(fileURLWithPath: cwd).appendingPathComponent("packages/Rules", isDirectory: true)
        if FileManager.default.fileExists(atPath: local.path) {
            return local
        }
        FileHandle.standardError.write(Data(
            "no rules directory found — pass --rules <dir> or set OWLWATCH_RULES.\n".utf8
        ))
        throw ExitCode(2)
    }

    // MARK: - Text output

    private func emitText(
        report: ScanReport,
        visible: [Finding],
        rulesURL: URL,
        minimumSeverity: Severity,
        captureElapsed: TimeInterval
    ) {
        var lines: [String] = []
        lines.append("Rules:    \(report.rulesEvaluated) loaded from \(rulesURL.path)")
        lines.append("Captured: snapshot in \(String(format: "%.3fs", captureElapsed))")
        lines.append("Scanned:  \(report.itemsEvaluated) items in \(String(format: "%.3fs", report.elapsed))")
        if visible.isEmpty {
            lines.append("Findings: none at severity >= \(minimumSeverity.rawValue)")
        } else {
            lines.append("Findings: \(visible.count) at severity >= \(minimumSeverity.rawValue)")
        }
        lines.append("")
        let sorted = visible.sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return $0.ruleID < $1.ruleID
        }
        for finding in sorted {
            lines.append("[\(finding.severity.displayName)] \(finding.ruleID) — \(finding.ruleName)")
            lines.append("  source: \(finding.source.rawValue)")
            lines.append("  target: \(finding.targetID)")
            if let mitre = finding.mitre {
                lines.append("  mitre:  \(mitre)")
            }
            if !finding.evidence.isEmpty {
                for (key, value) in finding.evidence.sorted(by: { $0.key < $1.key }) {
                    lines.append("  \(key) = \(value)")
                }
            }
            lines.append("")
        }
        FileHandle.standardOutput.write(Data(lines.joined(separator: "\n").utf8))
    }

    // MARK: - JSON output

    private func emitJSON(
        report: ScanReport,
        visible: [Finding],
        rulesURL: URL,
        captureElapsed: TimeInterval
    ) throws {
        let payload: [String: Any] = [
            "scanned_at": ISO8601DateFormatter().string(from: report.scannedAt),
            "rules_loaded": report.rulesEvaluated,
            "items_evaluated": report.itemsEvaluated,
            "capture_elapsed_seconds": captureElapsed,
            "elapsed_seconds": report.elapsed,
            "rules_directory": rulesURL.path,
            "findings": visible.map { finding -> [String: Any] in
                var dict: [String: Any] = [
                    "id": finding.ruleID,
                    "name": finding.ruleName,
                    "severity": finding.severity.rawValue,
                    "source": finding.source.rawValue,
                    "target": finding.targetID,
                    "evidence": finding.evidence
                ]
                if let mitre = finding.mitre {
                    dict["mitre"] = mitre
                }
                return dict
            }
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
