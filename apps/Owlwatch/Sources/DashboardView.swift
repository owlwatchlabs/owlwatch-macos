import OWLog
import SwiftUI

/// The M17 Dashboard section — the app "home". One scrolling view
/// with headline counts from every data source plus a recent-
/// activity list. Below: a quick-actions row that switches sections
/// via AppModel. Wrapped in the M17 SectionHeader for visual
/// consistency with the other sections.
struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Dashboard") {
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
                    summaryGrid
                    Divider()
                    recentActivitySection
                    Divider()
                    quickActionsSection
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task {
            if viewModel.lastRefresh == nil {
                await viewModel.refresh()
            }
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
                        primary: "\(viewModel.loginItemCount)",
                        secondary: "\(viewModel.loginItemEnabledCount) enabled"
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

    // MARK: - Quick actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick actions")
                .font(.title3.bold())
            HStack(spacing: 12) {
                NavigationButton(
                    title: "Processes",
                    symbol: "cpu"
                ) {
                    model.section = .processes
                }
                NavigationButton(
                    title: "Network",
                    symbol: "network"
                ) {
                    model.section = .network
                }
                NavigationButton(
                    title: "Persistence",
                    symbol: "play.circle"
                ) {
                    model.section = .persistence
                }
                NavigationButton(
                    title: "Devices",
                    symbol: "camera"
                ) {
                    model.section = .devices
                }
                NavigationButton(
                    title: "Logs",
                    symbol: "doc.text"
                ) {
                    model.section = .logs
                }
                NavigationButton(
                    title: "Inspector",
                    symbol: "doc.text.magnifyingglass"
                ) {
                    model.section = .inspector
                }
            }
        }
    }
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

private struct NavigationButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button {
            // LSUIElement apps need to activate explicitly when opening
            // a window from another window — the new one would appear
            // behind whatever's frontmost otherwise.
            NSApp.activate()
            action()
        } label: {
            Label(title, systemImage: symbol)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .controlSize(.large)
    }
}

private func timeString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.string(from: date)
}
