import OWLog
import SwiftUI

/// The M18 Overview section — the app "home". One scrolling view
/// with headline counts from every data source plus a recent-
/// activity list. Below: a quick-actions row that switches sections
/// via AppModel. Wrapped in the M17 SectionHeader for visual
/// consistency with the other sections.
///
/// Renamed from `DashboardView` in M18.1 — the enum case + the
/// header title + the sidebar label now all read "Overview" so
/// nothing stray says "Dashboard".
struct OverviewView: View {
    @State private var viewModel = OverviewViewModel()
    @State private var contentFilter = ContentFilterActivator()
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Overview") {
                if viewModel.deviceInUseCount > 0 {
                    Text("\(raw(viewModel.deviceInUseCount)) device\(viewModel.deviceInUseCount == 1 ? "" : "s") in use")
                        .font(.owlMono(11))
                        .foregroundStyle(Color.owlRed)
                }
                Spacer()
                refreshGroup
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    contentFilterCard
                    summaryGrid
                    Divider()
                    recentActivitySection
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task {
            if viewModel.lastRefresh == nil {
                await viewModel.refresh()
            }
            await contentFilter.reconcileFromPreferences()
        }
    }

    // MARK: - Content filter card (M7.1)

    /// Minimal status + install affordance for the M7 content filter.
    /// Scope here is intentionally tight — M7.3 will land richer
    /// flow visibility on the Network surface. This card just makes
    /// the activation flow reachable without a CLI.
    @ViewBuilder
    private var contentFilterCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "network.badge.shield.half.filled")
                .font(.title2)
                .foregroundStyle(filterStateColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("Content filter")
                    .font(.headline)
                Text(filterStateLabel)
                    .font(.owlMono(11))
                    .foregroundStyle(Color.owlTextMuted)
            }
            Spacer()
            Button(action: contentFilter.requestActivation) {
                Text(filterButtonLabel)
                    .font(.owlMono(12))
                    .foregroundStyle(Color.owlAmber)
            }
            .buttonStyle(.plain)
            .disabled(filterButtonDisabled)
        }
        .padding(12)
        .background(Color.owlSurface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.owlBorder, lineWidth: 1)
        )
    }

    private var filterStateColor: Color {
        switch contentFilter.state {
        case .enabled:                          return .owlGreen
        case .failed:                           return .owlRed
        case .willCompleteAfterReboot,
             .awaitingUserApproval:             return .owlAmber
        default:                                return .owlTextMuted
        }
    }

    private var filterStateLabel: String {
        switch contentFilter.state {
        case .idle:                         return "not installed"
        case .requestingActivation:         return "requesting activation…"
        case .awaitingUserApproval:         return "waiting on your approval in System Settings"
        case .configuringFilter:            return "configuring filter…"
        case .enabled:                      return "active · observing flows"
        case .willCompleteAfterReboot:      return "will finish after reboot"
        case .failed(let message):          return "failed: \(message)"
        }
    }

    private var filterButtonLabel: String {
        switch contentFilter.state {
        case .enabled:  return "reinstall"
        case .failed:   return "retry"
        default:        return "install"
        }
    }

    private var filterButtonDisabled: Bool {
        switch contentFilter.state {
        case .requestingActivation, .configuringFilter, .awaitingUserApproval:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private var refreshGroup: some View {
        if let last = viewModel.lastRefresh {
            Text("last refresh \(last.formatted(date: .omitted, time: .standard))")
                .font(.owlMono(11))
                .foregroundStyle(Color.owlTextDim)
        }
        Button {
            Task { await viewModel.refresh() }
        } label: {
            if viewModel.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(Color.owlTextMuted)
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
        .keyboardShortcut("r", modifiers: .command)
    }

    // MARK: - Summary grid

    private var summaryGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("System")
                .font(.title3.bold())

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                Button { model.section = .processes } label: {
                    SummaryCard(
                        icon: "cpu",
                        label: "Processes",
                        primary: "\(viewModel.processCount)",
                        secondary: "running"
                    )
                }.buttonStyle(.plain)
                Button { model.section = .persistence } label: {
                    SummaryCard(
                        icon: "play.circle",
                        label: "Launch services",
                        primary: "\(viewModel.launchServiceCount)",
                        secondary: "\(viewModel.launchServiceUserCount) in ~/Library/LaunchAgents"
                    )
                }.buttonStyle(.plain)
                Button { model.section = .persistence } label: {
                    SummaryCard(
                        icon: "person.circle",
                        label: "Login items",
                        primary: viewModel.loginItemCount.map(String.init) ?? "—",
                        secondary: viewModel.loginItemEnabledCount.map { "\($0) enabled" }
                            ?? "view in Persistence"
                    )
                }.buttonStyle(.plain)
                Button { model.section = .network } label: {
                    SummaryCard(
                        icon: "network",
                        label: "Network",
                        primary: "\(viewModel.networkEstablishedCount) active",
                        secondary: "\(viewModel.networkListenerCount) listeners"
                    )
                }.buttonStyle(.plain)
                Button { model.section = .devices } label: {
                    SummaryCard(
                        icon: "camera",
                        label: "Devices",
                        primary: "\(viewModel.cameraCount + viewModel.microphoneCount)",
                        secondary:
                            "\(viewModel.cameraCount) cam / \(viewModel.microphoneCount) mic"
                                + (viewModel.deviceInUseCount > 0
                                   ? " · \(viewModel.deviceInUseCount) in use"
                                   : "")
                    )
                }.buttonStyle(.plain)
            }
        }
    }

    // MARK: - Recent activity

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent activity (last 5 minutes)")
                .font(.title3.bold())

            if viewModel.recentTCCDenials.isEmpty && viewModel.recentErrorLogs.isEmpty {
                Text("No notable activity. The system has been quiet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                if !viewModel.recentTCCDenials.isEmpty {
                    ActivityGroup(
                        title: "TCC denials",
                        symbol: "lock.shield",
                        count: viewModel.recentTCCDenials.count
                    ) {
                        ForEach(viewModel.recentTCCDenials.prefix(5), id: \.msgID) { event in
                            DenialRow(event: event)
                        }
                    }
                }
                if !viewModel.recentErrorLogs.isEmpty {
                    ActivityGroup(
                        title: "Error / fault log entries",
                        symbol: "exclamationmark.triangle",
                        count: viewModel.recentErrorLogs.count
                    ) {
                        ForEach(viewModel.recentErrorLogs.prefix(5), id: \.activityID) { entry in
                            ErrorLogRow(entry: entry)
                        }
                    }
                }
            }
        }
    }

    // (Quick actions row removed in M18.2 — duplicated the sidebar and
    //  the summary cards above already drill into their sections.)
}

// MARK: - Reusable rows

private struct SummaryCard: View {
    let icon: String
    let label: String
    let primary: String
    let secondary: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(primary)
                    .font(.title2.bold())
                Text(secondary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ActivityGroup<Content: View>: View {
    let title: String
    let symbol: String
    let count: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("\(title) (\(count))", systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.secondary)
            content()
                .padding(.leading, 4)
        }
        .padding(.vertical, 4)
    }
}

private struct DenialRow: View {
    let event: TCCEvent
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(timeString(event.timestamp))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(event.service.rawValue)
                .font(.caption.monospaced())
                .frame(width: 220, alignment: .leading)
            Text(event.accessingProcess?.identifier ?? "(unknown)")
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }
}

private struct ErrorLogRow: View {
    let entry: LogEntry
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(timeString(entry.timestamp))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(entry.level == .fault ? "FAULT" : "ERROR")
                .font(.caption.bold().monospaced())
                .foregroundStyle(entry.level == .fault ? .red : .orange)
                .frame(width: 50, alignment: .leading)
            Text(entry.processName ?? "?")
                .font(.caption.monospaced())
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(entry.message)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
    }
}

private func timeString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.string(from: date)
}
