import OWNetwork
import SwiftUI

/// The M17 Network section. SectionHeader (with SubnavPicker over
/// `NetworkTab` + FilterField + refresh) on top; below, a nested
/// NavigationSplitView with center list + trailing detail.
struct NetworkView: View {
    @State private var viewModel = NetworkViewModel()
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Network") {
                SubnavPicker(
                    selection: $viewModel.selectedTab,
                    options: NetworkTab.allCases.map { ($0, $0.displayName) }
                )
                FilterField(text: $viewModel.searchText,
                            placeholder: "Filter by address, port, process, or state")
                    .frame(maxWidth: 360)
                Spacer()
                refreshGroup
            }
            NavigationSplitView {
                NetworkCenterPane(viewModel: viewModel)
                    .navigationSplitViewColumnWidth(min: 400, ideal: 520)
            } detail: {
                NetworkDetailPane(viewModel: viewModel)
                    .navigationSplitViewColumnWidth(min: 320, ideal: 380)
            }
        }
        .task {
            if viewModel.lastRefresh == nil {
                await viewModel.refresh()
            }
        }
        .onAppear { applyFocus() }
        .onChange(of: model.focus) { _, _ in applyFocus() }
    }

    /// Read a pending cross-link target set by another section
    /// (`process(pid)`) and pre-filter to that PID. Always clears
    /// `model.focus` so the same target doesn't reapply on the next
    /// section switch.
    private func applyFocus() {
        guard case .process(let pid, _)? = model.focus else { return }
        viewModel.searchText = raw(pid)
        viewModel.selectedTab = .all
        model.focus = nil
    }

    @ViewBuilder
    private var refreshGroup: some View {
        if let last = viewModel.lastRefresh {
            let when = last.formatted(date: .omitted, time: .standard)
            Text("last refresh \(when) · \(grouped(viewModel.connections.count)) sockets")
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
}

// MARK: - Center pane

private struct NetworkCenterPane: View {
    @Bindable var viewModel: NetworkViewModel

    var body: some View {
        let items = viewModel.visibleConnections
        if items.isEmpty {
            ContentUnavailableView(
                viewModel.searchText.isEmpty
                    ? "No \(viewModel.selectedTab.displayName)"
                    : "No Matches",
                systemImage: viewModel.selectedTab.symbolName,
                description: Text(viewModel.searchText.isEmpty
                                  ? emptyStateBody(for: viewModel.selectedTab)
                                  : "Filter '\(viewModel.searchText)' matched nothing.")
            )
        } else {
            List(items,
                 id: \.self,
                 selection: $viewModel.selectedKey) { connection in
                NetworkRow(connection: connection,
                           processName: viewModel.processNames[connection.pid])
                    .tag(viewModel.connectionKey(connection))
            }
            .listStyle(.inset)
        }
    }

    private func emptyStateBody(for tab: NetworkTab) -> String {
        switch tab {
        case .all: return "OWNetwork.snapshot() returned no sockets."
        case .listeners: return "No process on this box is listening for incoming connections."
        case .tcp: return "No TCP sockets open."
        case .udp: return "No UDP sockets open."
        case .unix: return "No Unix-domain sockets visible to this user."
        }
    }
}

private struct NetworkRow: View {
    let connection: Connection
    let processName: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(protoLabel)
                .font(.caption.monospaced())
                .frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(localEndpoint)
                    .font(.body.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(remoteEndpoint)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(processName ?? "?")
                    .font(.caption)
                    .lineLimit(1)
                Text("pid \(connection.pid)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            if let state = connection.tcpState {
                Text(state.displayName)
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(stateBackground(state).opacity(0.18))
                    .clipShape(Capsule())
            } else if connection.isListener {
                Text("LISTEN")
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.18))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    private var protoLabel: String {
        switch (connection.family, connection.protocol) {
        case (.ipv4, .tcp): return "tcp4"
        case (.ipv6, .tcp): return "tcp6"
        case (.ipv4, .udp): return "udp4"
        case (.ipv6, .udp): return "udp6"
        case (.unix, .unixStream): return "unix-s"
        case (.unix, .unixDatagram): return "unix-d"
        default: return connection.protocol.rawValue
        }
    }

    private var localEndpoint: String {
        renderEndpoint(family: connection.family,
                       address: connection.localAddress,
                       port: connection.localPort)
    }

    private var remoteEndpoint: String {
        let rendered = renderEndpoint(family: connection.family,
                                       address: connection.remoteAddress,
                                       port: connection.remotePort)
        if connection.family != .unix && connection.remoteAddress == nil {
            return "← \(rendered)"
        }
        return "→ \(rendered)"
    }

    private func stateBackground(_ state: TCPState) -> Color {
        switch state {
        case .established: return .green
        case .listen: return .blue
        case .closeWait, .finWait1, .finWait2, .closing, .timeWait, .lastAck: return .orange
        case .closed: return .secondary
        default: return .secondary
        }
    }
}

// MARK: - Detail pane

private struct NetworkDetailPane: View {
    @Bindable var viewModel: NetworkViewModel

    var body: some View {
        if let connection = viewModel.selectedConnection {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(viewModel.processNames[connection.pid] ?? "pid \(connection.pid)")
                        .font(.title2).bold()
                    Divider()
                    DetailField("Protocol", protocolLabel(connection))
                    DetailField("Local",
                                renderEndpoint(family: connection.family,
                                               address: connection.localAddress,
                                               port: connection.localPort))
                    DetailField("Remote",
                                renderEndpoint(family: connection.family,
                                               address: connection.remoteAddress,
                                               port: connection.remotePort))
                    if let state = connection.tcpState {
                        DetailField("TCP State", state.displayName)
                    } else if connection.isListener {
                        DetailField("State", "LISTENING")
                    }
                    Divider()
                    DetailField("Process", viewModel.processNames[connection.pid] ?? "(unknown)")
                    DetailField("PID", String(connection.pid))
                    DetailField("File descriptor", String(connection.fd))
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView(
                "Select a connection",
                systemImage: "list.bullet.indent",
                description: Text("Pick a socket on the left to see its details.")
            )
        }
    }

    private func protocolLabel(_ connection: Connection) -> String {
        switch (connection.family, connection.protocol) {
        case (.ipv4, .tcp): return "TCP/IPv4"
        case (.ipv6, .tcp): return "TCP/IPv6"
        case (.ipv4, .udp): return "UDP/IPv4"
        case (.ipv6, .udp): return "UDP/IPv6"
        case (.unix, .unixStream): return "Unix-domain stream"
        case (.unix, .unixDatagram): return "Unix-domain datagram"
        default: return "\(connection.family.rawValue) / \(connection.protocol.rawValue)"
        }
    }
}

// MARK: - Shared helpers

/// Render a host:port endpoint string the way `owlwatch netstat` does:
/// IP addresses unbracketed except IPv6 (where the colons need
/// `[...]` disambiguation), `*` for wildcards, full path for Unix
/// sockets.
private func renderEndpoint(family: AddressFamily, address: String?, port: UInt16?) -> String {
    if family == .unix {
        return address ?? "(anonymous)"
    }
    let host: String
    if let address {
        host = address.contains(":") ? "[\(address)]" : address
    } else {
        host = "*"
    }
    let portStr = port.map(String.init) ?? "*"
    return "\(host):\(portStr)"
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
