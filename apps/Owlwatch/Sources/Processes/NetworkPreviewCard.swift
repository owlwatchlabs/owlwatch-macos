import OWNetwork
import OWTriage
import SwiftUI

/// Inline preview of a process's open sockets inside the dossier's
/// Linked section.
///
/// Replaces the single-line "Network · sockets owned by pid N →"
/// link with a tinted card whose body lists each socket: scope ·
/// remote · state. Public-internet sockets sort to the top so the
/// most triage-relevant rows are always visible without expanding.
/// "open →" in the header navigates to the full Network section
/// filtered to this pid.
///
/// Tiered disclosure (paged in place, no navigation):
/// - N ≤ 10: show all, no control
/// - N > 10 collapsed: show 10 + "expand"
/// - Expanded: show up to 50 + "collapse"
/// - N > 50: show 50 + "showing 50 of N · open in Network →"
struct NetworkPreviewCard: View {
    let pid: pid_t
    let processName: String
    let connections: [Connection]
    let onOpenInNetwork: () -> Void

    /// Tunable caps. Named for the spec's `previewCollapsedLimit` /
    /// `previewExpandedLimit` so future product-tuning lands here.
    private let previewCollapsedLimit = 10
    private let previewExpandedLimit = 50

    @State private var expanded = false

    var body: some View {
        // Always render the same card chrome — the empty-state
        // variant just drops the column headers and the per-row
        // list, keeping the header + caveat so the dossier doesn't
        // change shape between "no sockets" and "lots of sockets".
        VStack(alignment: .leading, spacing: 8) {
            header
            if !connections.isEmpty {
                Divider().overlay(Color.owlBorder)
                columnHeaders
                ForEach(visibleRows, id: \.fd) { conn in
                    ConnectionRow(connection: conn)
                }
            } else {
                Text("no sockets")
                    .font(.owlMono(12))
                    .foregroundStyle(Color.owlTextMuted)
            }
            footer
        }
        .padding(12)
        .background(Color.owlSurface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.owlBorder, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("NETWORK · \(connections.count) socket\(connections.count == 1 ? "" : "s")")
                .font(.owlMono(11).bold())
                .tracking(0.6)
                .foregroundStyle(Color.owlAmber)
            Spacer()
            Button(action: onOpenInNetwork) {
                HStack(spacing: 3) {
                    Text("open")
                    Text("→")
                }
                .font(.owlMono(11))
                .foregroundStyle(Color.owlTextDim)
            }
            .buttonStyle(.plain)
        }
    }

    /// Column-header row: `scope · proto · remote · state · fd`.
    /// Tracks the layout of `ConnectionRow` so labels and values
    /// line up visually.
    private var columnHeaders: some View {
        HStack(spacing: 10) {
            Text("scope")
                .frame(width: 64, alignment: .leading)
            Text("proto")
                .frame(width: 48, alignment: .leading)
            Text("remote")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("state · fd")
                .frame(width: 130, alignment: .trailing)
        }
        .font(.owlMono(10.5))
        .foregroundStyle(Color.owlTextDim)
    }

    // MARK: - Rows

    /// Sort + cap the rows for display. Public-internet first so
    /// the row that matters most is always visible without
    /// expanding; everything else falls back to a stable order
    /// (LAN, localhost, IPC, unknown) and ties break by fd.
    private var sortedConnections: [Connection] {
        connections.sorted { a, b in
            let sa = NetworkScope(a).sortRank
            let sb = NetworkScope(b).sortRank
            if sa != sb { return sa < sb }
            return a.fd < b.fd
        }
    }

    private var visibleRows: [Connection] {
        let sorted = sortedConnections
        let limit: Int
        if sorted.count <= previewCollapsedLimit {
            limit = sorted.count
        } else if expanded {
            limit = min(previewExpandedLimit, sorted.count)
        } else {
            limit = previewCollapsedLimit
        }
        return Array(sorted.prefix(limit))
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        let total = connections.count
        // No control when everything's already visible.
        if total <= previewCollapsedLimit {
            triageNote
        } else if expanded {
            if total > previewExpandedLimit {
                Button(action: onOpenInNetwork) {
                    HStack(spacing: 3) {
                        Text("showing \(previewExpandedLimit) of \(total)")
                        Text("·")
                        Text("open in Network →")
                            .foregroundStyle(Color.owlAmber)
                    }
                    .font(.owlMono(11))
                    .foregroundStyle(Color.owlTextDim)
                }
                .buttonStyle(.plain)
            }
            collapseButton
            triageNote
        } else {
            expandButton
            triageNote
        }
    }

    private var expandButton: some View {
        Button {
            expanded = true
        } label: {
            Text("expand")
                .font(.owlMono(11))
                .foregroundStyle(Color.owlTextDim)
        }
        .buttonStyle(.plain)
    }

    private var collapseButton: some View {
        Button {
            expanded = false
        } label: {
            Text("collapse")
                .font(.owlMono(11))
                .foregroundStyle(Color.owlTextDim)
        }
        .buttonStyle(.plain)
    }

    /// Faithfulness caveat — mirrors the §7 brief guardrails. The
    /// preview is a point-in-time snapshot of the raw addresses;
    /// no DNS, no service guessing, no flow inspection.
    private var triageNote: some View {
        Text("point-in-time snapshot · raw addresses, no DNS · traffic not inspected")
            .font(.owlMono(10.5))
            .foregroundStyle(Color.owlTextDim)
            .padding(.top, 2)
    }
}

// MARK: - Connection row

private struct ConnectionRow: View {
    let connection: Connection

    var body: some View {
        HStack(spacing: 10) {
            // scope
            let scope = NetworkScope(connection)
            Text(scope.label)
                .foregroundStyle(scope.previewColor)
                .frame(width: 64, alignment: .leading)
            // proto
            Text(protoLabel)
                .foregroundStyle(Color.owlTextMuted)
                .frame(width: 48, alignment: .leading)
            // remote
            Text(remoteLabel)
                .foregroundStyle(scope == .internetPublic ? Color.owlText : Color.owlTextMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            // state · fd (trailing)
            Text(stateAndFd)
                .foregroundStyle(Color.owlTextDim)
                .frame(width: 130, alignment: .trailing)
        }
        .font(.owlMono(12))
    }

    private var protoLabel: String {
        switch connection.protocol {
        case .tcp:          return connection.family == .ipv6 ? "tcp6" : "tcp4"
        case .udp:          return connection.family == .ipv6 ? "udp6" : "udp4"
        case .unixStream:   return "unix"
        case .unixDatagram: return "unix"
        }
    }

    /// Raw remote endpoint — IP:port for IP sockets, the bound
    /// filesystem path for Unix sockets. No DNS, no service guess
    /// (per §7 guardrails). Listeners with no remote fall back to
    /// the wildcard binding.
    private var remoteLabel: String {
        if connection.family == .unix {
            return connection.localAddress ?? "(anonymous)"
        }
        if let addr = connection.remoteAddress, let port = connection.remotePort {
            return formatIPPort(address: addr, port: port)
        }
        if let addr = connection.localAddress, let port = connection.localPort {
            return formatIPPort(address: addr, port: port)
        }
        return "—"
    }

    /// IPv6 addresses get bracketed so the `:port` reads as
    /// a separator and not as part of the hex address.
    private func formatIPPort(address: String, port: UInt16) -> String {
        if address.contains(":") {
            return "[\(address)]:\(port)"
        }
        return "\(address):\(port)"
    }

    private var stateAndFd: String {
        let fd = "fd \(connection.fd)"
        guard let tcpState = connection.tcpState else { return fd }
        // Lowercase for the chrome — matches the mock's tone.
        return "\(tcpState.displayName.lowercased()) · \(fd)"
    }
}

// MARK: - NetworkScope styling for the preview

private extension NetworkScope {
    /// Sort key — public-internet rows surface first.
    var sortRank: Int {
        switch self {
        case .internetPublic: return 0
        case .lan:            return 1
        case .localhost:      return 2
        case .ipc:            return 3
        case .unknown:        return 4
        }
    }

    /// Per-scope emphasis for the preview row — slightly different
    /// from `TriageStyles`' generic `.color` because the preview
    /// distinguishes localhost / IPC (both `owlTextDim`) from LAN
    /// (`owlTextMuted`) where the generic mapping conflates them.
    var previewColor: Color {
        switch self {
        case .internetPublic: return .owlBlue
        case .lan:            return .owlTextMuted
        case .localhost:      return .owlTextDim
        case .ipc:            return .owlTextDim
        case .unknown:        return .owlTextDim
        }
    }
}
