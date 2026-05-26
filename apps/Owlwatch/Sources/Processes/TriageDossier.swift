import OWPersistence
import OWProcess
import OWRules
import OWTriage
import SwiftUI

/// The M18.5 rules-first dossier — what replaces the M17.6 detail
/// pane for a selected process.
///
/// Section order is deliberately triage-first: findings sit above
/// identity facts because the question the user is answering is
/// "what is interesting about this process," not "what is its pid."
/// Mach-O is a collapsed expander at the bottom; loading is lazy.
///
/// Heavy detail (argv, open files) is sourced from the existing
/// `ProcessesViewModel` so the dossier stays free of the M2/M17
/// snapshot path and lets that VM remain authoritative for its
/// fields.
struct TriageDossier: View {
    let row: ProcessRowVM
    @ObservedObject var listModel: ProcessListModel
    @Bindable var viewModel: ProcessesViewModel
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                findingsSection
                identitySection
                if !listModel.launchServices(for: row.pid).isEmpty {
                    persistenceSection
                }
                linkedSection
                MachOExpander(path: row.path)
                argumentsSection
                openFilesSection
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if row.maxSeverity != nil {
                    Circle()
                        .fill(row.severityColor)
                        .frame(width: 8, height: 8)
                }
                Text(row.name)
                    .font(.title2).bold()
                    .foregroundStyle(Color.owlText)
            }
            HStack(spacing: 8) {
                Text("pid \(raw(row.pid))")
                    .font(.owlMono(12))
                    .foregroundStyle(Color.owlTextMuted)
                Text("·").foregroundStyle(Color.owlTextDim)
                Text(row.signer.label)
                    .font(.owlMono(12))
                    .foregroundStyle(row.signer.color)
                if row.isPersistent {
                    Text("·").foregroundStyle(Color.owlTextDim)
                    Text("persistent")
                        .font(.owlMono(12))
                        .foregroundStyle(Color.owlAmber)
                }
            }
        }
    }

    @ViewBuilder
    private var findingsSection: some View {
        let findings = listModel.findings(for: row.pid)
        DossierSection("Findings", count: findings.isEmpty ? nil : findings.count)
        if findings.isEmpty {
            Text("No rules triggered.")
                .font(.owlMono(12))
                .foregroundStyle(Color.owlTextDim)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(findings, id: \.ruleID) { finding in
                    FindingCard(finding: finding)
                }
            }
        }
    }

    @ViewBuilder
    private var identitySection: some View {
        DossierSection("Identity")
        VStack(alignment: .leading, spacing: 4) {
            KeyValueRow(key: "PID", value: raw(row.pid))
            KeyValueRow(key: "Parent PID", value: raw(row.parentPid))
            KeyValueRow(key: "User ID", value: raw(row.userId))
            KeyValueRow(key: "Path", value: row.path ?? "—")
        }
    }

    @ViewBuilder
    private var persistenceSection: some View {
        let entries = listModel.launchServices(for: row.pid)
        DossierSection("Persistence", count: entries.count)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(entries, id: \.plistPath) { entry in
                LaunchServiceRow(entry: entry)
            }
        }
    }

    @ViewBuilder
    private var linkedSection: some View {
        DossierSection("Linked")
        VStack(alignment: .leading, spacing: 6) {
            LinkedRow(
                icon: "globe",
                label: "Network · sockets owned by pid \(raw(row.pid))",
                tint: .owlBlue
            ) {
                app.focus = .process(pid: row.pid, name: row.name)
                app.section = .network
            }
            if let path = row.path {
                LinkedRow(
                    icon: "doc.text.magnifyingglass",
                    label: "Inspector · \((path as NSString).lastPathComponent)",
                    tint: .owlAmber
                ) {
                    app.focus = .binary(URL(fileURLWithPath: path))
                    app.section = .inspector
                }
            }
            LinkedRow(
                icon: "lock.shield",
                label: "Logs · TCC events for \(row.name)",
                tint: .owlGreen
            ) {
                app.focus = .process(pid: row.pid, name: row.name)
                app.section = .logs
            }
        }
    }

    @ViewBuilder
    private var argumentsSection: some View {
        DossierSection("Arguments")
        if viewModel.detailLoading {
            ProgressView().controlSize(.small)
        } else if let args = viewModel.detailProcess?.arguments, !args.isEmpty {
            Text(args.joined(separator: " "))
                .font(.owlMono(12))
                .foregroundStyle(Color.owlText)
                .textSelection(.enabled)
        } else if viewModel.detailProcess != nil {
            // Snapshot succeeded but argv is empty / unreadable.
            Text("(none)")
                .font(.owlMono(12))
                .foregroundStyle(Color.owlTextDim)
        } else {
            // Snapshot returned nil — process exited mid-load, or
            // we lack permission. Either way: not "loading", just
            // unavailable.
            Text("(unavailable)")
                .font(.owlMono(12))
                .foregroundStyle(Color.owlTextDim)
        }
    }

    @ViewBuilder
    private var openFilesSection: some View {
        let count = viewModel.detailProcess?.openFiles?.count ?? 0
        DossierSection("Open files", count: count > 0 ? count : nil)
        if viewModel.detailLoading {
            ProgressView().controlSize(.small)
        } else if let files = viewModel.detailProcess?.openFiles, !files.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                    Text(renderOpenFile(file))
                        .font(.owlMono(11))
                        .foregroundStyle(Color.owlTextMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        } else if viewModel.detailProcess != nil {
            Text("(none visible to this user)")
                .font(.owlMono(12))
                .foregroundStyle(Color.owlTextDim)
        } else {
            Text("(unavailable)")
                .font(.owlMono(12))
                .foregroundStyle(Color.owlTextDim)
        }
    }

    // MARK: - Helpers

    private func renderOpenFile(_ file: OpenFile) -> String {
        switch file {
        case .file(let fd, let path):
            return "fd \(fd): \(path ?? "(unnamed vnode)")"
        case .socket(let fd, let family, let type):
            return "fd \(fd): socket (family=\(family), type=\(type))"
        case .pipe(let fd):
            return "fd \(fd): pipe"
        case .other(let fd, let rawType):
            return "fd \(fd): other (type=\(rawType))"
        }
    }
}

// MARK: - Section header

/// Caption-bold label with an optional trailing count chip. Matches
/// the M18.4 list status row's tone — small, muted, no shouting.
/// Named `DossierSection` (not `SectionHeader`) to avoid colliding
/// with SwiftUI's built-in `SectionHeader`.
private struct DossierSection: View {
    let title: String
    let count: Int?

    init(_ title: String, count: Int? = nil) {
        self.title = title
        self.count = count
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(Color.owlTextMuted)
            if let count {
                Text("\(count)")
                    .font(.owlMono(11))
                    .foregroundStyle(Color.owlTextDim)
            }
            Spacer()
            Rectangle()
                .fill(Color.owlBorder)
                .frame(height: 0.5)
                .padding(.leading, 4)
        }
    }
}

// MARK: - Finding card

/// One rule finding rendered as a vertically-stacked card: severity
/// badge + rule name on top, evidence k/v rows beneath. Evidence is
/// rendered as plain k=v pairs since the brief asks for facts, not
/// "THREAT" labels.
private struct FindingCard: View {
    let finding: Finding

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(finding.severity.label)
                    .font(.owlMono(10).bold())
                    .foregroundStyle(finding.severity.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(finding.severity.color.opacity(0.5), lineWidth: 0.5)
                    )
                Text(finding.ruleName)
                    .font(.body)
                    .foregroundStyle(Color.owlText)
                Spacer()
                if let mitre = finding.mitre {
                    Text(mitre)
                        .font(.owlMono(10))
                        .foregroundStyle(Color.owlTextDim)
                }
            }
            if !finding.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(finding.evidence.sorted(by: { $0.key < $1.key }), id: \.key) { pair in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(pair.key)
                                .font(.owlMono(11))
                                .foregroundStyle(Color.owlTextMuted)
                            Text(pair.value)
                                .font(.owlMono(11))
                                .foregroundStyle(Color.owlText)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color.owlSurfaceHi, in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.owlBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - LaunchService row

private struct LaunchServiceRow: View {
    let entry: LaunchService

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(entry.label ?? "(no label)")
                    .font(.owlMono(12))
                    .foregroundStyle(Color.owlText)
                Spacer()
                Text(entry.scope.runsAsRoot ? "daemon" : "agent")
                    .font(.owlMono(10))
                    .foregroundStyle(Color.owlTextDim)
            }
            Text(entry.plistPath)
                .font(.owlMono(11))
                .foregroundStyle(Color.owlTextMuted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
