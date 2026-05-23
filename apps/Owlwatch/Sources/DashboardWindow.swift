import OWLog
import SwiftUI

/// The M16.1 status dashboard — the new app "home". A single
/// scrolling view that surfaces headline counts from every data
/// source plus a recent-activity list. Designed to be the first
/// thing the user sees when they open Owlwatch.
///
/// Navigation links across the bottom open the dedicated per-source
/// windows (Persistence, Devices, and the M16.2+ windows as they
/// land).
struct DashboardWindow: View {
    @State private var viewModel = DashboardViewModel()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                Divider()
                summaryGrid
                Divider()
                recentActivitySection
                Divider()
                quickActionsSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Owlwatch")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    if viewModel.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(viewModel.isLoading)
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        .frame(minWidth: 720, minHeight: 540)
        .task {
            if viewModel.lastRefresh == nil {
                await viewModel.refresh()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "shield.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 28))
                Text("Owlwatch Status")
                    .font(.largeTitle.bold())
                Spacer()
                if viewModel.deviceInUseCount > 0 {
                    Label("\(viewModel.deviceInUseCount) device(s) in use",
                          systemImage: "dot.radiowaves.left.and.right")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.red.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            if let lastRefresh = viewModel.lastRefresh {
                Text("Last refresh: \(lastRefresh.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Summary grid

    private var summaryGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("System")
                .font(.title3.bold())

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                SummaryCard(
                    icon: "cpu",
                    label: "Processes",
                    primary: "\(viewModel.processCount)",
                    secondary: "running"
                )
                SummaryCard(
                    icon: "play.circle",
                    label: "Launch services",
                    primary: "\(viewModel.launchServiceCount)",
                    secondary: "\(viewModel.launchServiceUserCount) in ~/Library/LaunchAgents"
                )
                SummaryCard(
                    icon: "person.circle",
                    label: "Login items",
                    primary: "\(viewModel.loginItemCount)",
                    secondary: "\(viewModel.loginItemEnabledCount) enabled"
                )
                SummaryCard(
                    icon: "network",
                    label: "Network",
                    primary: "\(viewModel.networkEstablishedCount) active",
                    secondary: "\(viewModel.networkListenerCount) listeners"
                )
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
                    openWindow(id: OwlwatchApp.processesWindowID)
                }
                NavigationButton(
                    title: "Network",
                    symbol: "network"
                ) {
                    openWindow(id: OwlwatchApp.networkWindowID)
                }
                NavigationButton(
                    title: "Persistence",
                    symbol: "play.circle"
                ) {
                    openWindow(id: OwlwatchApp.persistenceWindowID)
                }
                NavigationButton(
                    title: "Devices",
                    symbol: "camera"
                ) {
                    openWindow(id: OwlwatchApp.devicesWindowID)
                }
                NavigationButton(
                    title: "Logs",
                    symbol: "doc.text"
                ) {
                    openWindow(id: OwlwatchApp.logsWindowID)
                }
                NavigationButton(
                    title: "Inspector",
                    symbol: "doc.text.magnifyingglass"
                ) {
                    openWindow(id: OwlwatchApp.binaryInspectorWindowID)
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
