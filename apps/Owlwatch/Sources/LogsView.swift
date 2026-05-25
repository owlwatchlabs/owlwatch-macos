import OWLog
import SwiftUI

/// The M17 Logs section. Three tabs (All Logs / TCC Events / Live
/// Tail). SectionHeader with SubnavPicker over `LogsTab` + the
/// Apply / Start Tail button; below it the existing LogsFilterBar
/// (predicate + level controls) and the center list + trailing
/// detail. The per-window sub-sidebar from M16.4 is gone — its
/// tabs are now the segmented sub-nav.
struct LogsView: View {
    @State private var viewModel = LogsViewModel()

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Logs") {
                SubnavPicker(
                    selection: $viewModel.selectedTab,
                    options: LogsTab.allCases.map { ($0, $0.displayName) }
                )
                Spacer()
                applyGroup
            }
            LogsFilterBar(viewModel: viewModel)
            Divider()
            NavigationSplitView {
                LogsCenterPane(viewModel: viewModel)
                    .navigationSplitViewColumnWidth(min: 420, ideal: 560)
            } detail: {
                LogsDetailPane(viewModel: viewModel)
                    .navigationSplitViewColumnWidth(min: 320, ideal: 400)
            }
        }
        .onDisappear {
            viewModel.stopLiveTail()
        }
    }

    @ViewBuilder
    private var applyGroup: some View {
        if let last = viewModel.lastRefresh {
            let when = last.formatted(date: .omitted, time: .standard)
            Text("last \(when) · \(viewModel.selectedTab.displayName)")
                .font(.owlMono(11))
                .foregroundStyle(Color.owlTextDim)
        }
        Button {
            Task { await viewModel.apply() }
        } label: {
            if viewModel.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: viewModel.selectedTab == .live
                      ? "dot.radiowaves.left.and.right"
                      : "arrow.clockwise")
                    .foregroundStyle(Color.owlTextMuted)
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
        .keyboardShortcut("r", modifiers: .command)
    }
}

// MARK: - Filter bar

private struct LogsFilterBar: View {
    @Bindable var viewModel: LogsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if viewModel.selectedTab != .live {
                    Picker("Lookback", selection: $viewModel.lookback) {
                        ForEach(LookbackWindow.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 180)
                }
                TextField("subsystem", text: $viewModel.subsystemFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                TextField("process", text: $viewModel.processFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                Spacer()
            }
            HStack(spacing: 12) {
                if viewModel.selectedTab == .all || viewModel.selectedTab == .live {
                    TextField("message contains", text: $viewModel.messageContains)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                    Toggle("Info", isOn: $viewModel.includeInfo)
                    Toggle("Debug", isOn: $viewModel.includeDebug)
                }
                if viewModel.selectedTab == .all {
                    Toggle("Errors only", isOn: $viewModel.errorsOnly)
                }
                if viewModel.selectedTab == .tcc {
                    Toggle("Denied only", isOn: $viewModel.deniedOnly)
                }
                Spacer()
            }
            if let error = viewModel.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Center pane

private struct LogsCenterPane: View {
    @Bindable var viewModel: LogsViewModel

    var body: some View {
        switch viewModel.selectedTab {
        case .all: AllLogsList(viewModel: viewModel)
        case .tcc: TCCEventsList(viewModel: viewModel)
        case .live: LiveLogsList(viewModel: viewModel)
        }
    }
}

private struct AllLogsList: View {
    @Bindable var viewModel: LogsViewModel

    var body: some View {
        if viewModel.logEntries.isEmpty {
            ContentUnavailableView(
                "No Log Entries",
                systemImage: "doc.text",
                description: Text(viewModel.lastRefresh == nil
                                  ? "Set filters above and press Apply (⌘R) to query."
                                  : "No entries matched. Widen the lookback or relax the filters.")
            )
        } else {
            List(Array(viewModel.logEntries.enumerated()),
                 id: \.offset,
                 selection: $viewModel.selectedItemID) { offset, entry in
                LogEntryRow(entry: entry)
                    .tag(viewModel.logEntryID(entry, index: offset))
            }
            .listStyle(.inset)
        }
    }
}

private struct LiveLogsList: View {
    @Bindable var viewModel: LogsViewModel

    var body: some View {
        if viewModel.liveEntries.isEmpty {
            ContentUnavailableView(
                "Live Tail",
                systemImage: "dot.radiowaves.left.and.right",
                description: Text("Set predicate filters above and press Start Tail (⌘R) to begin streaming.")
            )
        } else {
            List(Array(viewModel.liveEntries.enumerated()),
                 id: \.offset,
                 selection: $viewModel.selectedItemID) { offset, entry in
                LogEntryRow(entry: entry)
                    .tag(viewModel.logEntryID(entry, index: offset))
            }
            .listStyle(.inset)
        }
    }
}

private struct TCCEventsList: View {
    @Bindable var viewModel: LogsViewModel

    var body: some View {
        if viewModel.tccEvents.isEmpty {
            ContentUnavailableView(
                "No TCC Events",
                systemImage: "lock.shield",
                description: Text(viewModel.lastRefresh == nil
                                  ? "Set filters above and press Apply (⌘R) to query."
                                  : "No TCC transactions matched in the lookback window.")
            )
        } else {
            List(viewModel.tccEvents,
                 id: \.msgID,
                 selection: $viewModel.selectedItemID) { event in
                TCCEventRow(event: event)
                    .tag(viewModel.tccEventID(event))
            }
            .listStyle(.inset)
        }
    }
}

private struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(timeString(entry.timestamp))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(levelLabel(entry.level))
                .font(.caption.bold().monospaced())
                .foregroundStyle(levelColor(entry.level))
                .frame(width: 60, alignment: .leading)
            Text(entry.processName ?? "?")
                .font(.caption.monospaced())
                .frame(width: 140, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(entry.message)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
        .padding(.vertical, 1)
    }
}

private struct TCCEventRow: View {
    let event: TCCEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(timeString(event.timestamp))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(event.outcome.displayName)
                .font(.caption.bold().monospaced())
                .foregroundStyle(outcomeColor(event.outcome))
                .frame(width: 90, alignment: .leading)
            Text(event.service.rawValue)
                .font(.caption.monospaced())
                .frame(width: 220, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(event.accessingProcess?.identifier ?? "(unknown)")
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }
}

// MARK: - Detail pane

private struct LogsDetailPane: View {
    @Bindable var viewModel: LogsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let entry = viewModel.selectedLogEntry {
                    Text(entry.processName ?? "Log entry").font(.title2).bold()
                    Divider()
                    DetailField("Timestamp", entry.timestamp.formatted(date: .abbreviated, time: .standard))
                    DetailField("Level", levelLabel(entry.level))
                    DetailField("Event type", entry.eventType.rawValue)
                    DetailField("Subsystem", entry.subsystem ?? "—")
                    DetailField("Category", entry.category ?? "—")
                    DetailField("Process", entry.processName ?? "—")
                    DetailField("Process Path", entry.processPath ?? "—")
                    DetailField("PID", entry.processID.map(String.init) ?? "—")
                    Divider()
                    Text("Message")
                        .font(.caption2.bold()).foregroundStyle(.secondary)
                    Text(entry.message)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                } else if let event = viewModel.selectedTCCEvent {
                    Text("TCC: \(event.outcome.displayName)")
                        .font(.title2).bold()
                    Divider()
                    DetailField("Service", event.service.rawValue)
                    DetailField("Timestamp", event.timestamp.formatted(date: .abbreviated, time: .standard))
                    DetailField("Preflight", event.isPreflight ? "yes" : "no")
                    DetailField("msgID", event.msgID)
                    Divider()
                    Text("Accessing process").font(.caption2.bold()).foregroundStyle(.secondary)
                    DetailField("Identifier", event.accessingProcess?.identifier ?? "—")
                    DetailField("PID", event.accessingProcess.map { String($0.pid) } ?? "—")
                    DetailField("Binary",
                                event.accessingProcess?.binaryPath ?? "—")
                    if !event.isDirectRequest, let requesting = event.requestingProcess {
                        Divider()
                        Text("Requesting process (brokered)")
                            .font(.caption2.bold()).foregroundStyle(.secondary)
                        DetailField("Identifier", requesting.identifier)
                        DetailField("PID", String(requesting.pid))
                        DetailField("Binary", requesting.binaryPath)
                    }
                } else {
                    ContentUnavailableView(
                        "Select an entry",
                        systemImage: "list.bullet.indent",
                        description: Text("Pick a row on the left to see its details.")
                    )
                    .padding()
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Shared helpers

private func timeString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.string(from: date)
}

private func levelLabel(_ level: LogLevel) -> String {
    switch level {
    case .default: return "default"
    case .info: return "info"
    case .debug: return "debug"
    case .error: return "ERROR"
    case .fault: return "FAULT"
    }
}

private func levelColor(_ level: LogLevel) -> Color {
    switch level {
    case .fault: return .red
    case .error: return .orange
    case .debug: return .secondary
    case .info: return .blue
    case .default: return .primary
    }
}

private func outcomeColor(_ outcome: TCCOutcome) -> Color {
    switch outcome {
    case .denied: return .red
    case .allowed, .allowedLimited: return .green
    case .unknown: return .secondary
    }
}

private struct DetailField: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospaced())
                .textSelection(.enabled)
        }
    }
}
