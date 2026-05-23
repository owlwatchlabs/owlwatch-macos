import Darwin
import Foundation
import OWNetwork
import OWProcess

/// Drives the M16.3 Network window. Snapshot of every visible socket
/// (M4's `OWNetwork.snapshot()`) joined with a per-process name lookup
/// (M1's `OWProcess.all(...)`) so the connection list can show the
/// owning process at a glance — no per-row lookup latency.
///
/// Pull-on-demand refresh. Network state changes minute-by-minute,
/// not millisecond-by-millisecond; a live stream would just churn
/// the view without adding information the analyst can act on.
@MainActor
@Observable
final class NetworkViewModel {
    var connections: [Connection] = []

    /// Process name lookup keyed by PID. Rebuilt on every refresh
    /// alongside the connection snapshot so list rendering doesn't
    /// have to fetch per-row.
    var processNames: [pid_t: String] = [:]

    /// Active sidebar tab.
    var selectedTab: NetworkTab = .all

    /// Selected connection's stable key (`pid + fd`). Drives the
    /// detail pane.
    var selectedKey: String?

    /// Free-text filter against address / port / process name / state.
    var searchText: String = ""

    var isLoading: Bool = false
    var lastRefresh: Date?

    /// Filter applied to ``connections`` for the active tab + search.
    var visibleConnections: [Connection] {
        let tabFiltered = connections.filter { connection in
            switch selectedTab {
            case .all: return true
            case .listeners: return connection.isListener
            case .tcp: return connection.protocol == .tcp
            case .udp: return connection.protocol == .udp
            case .unix:
                return connection.protocol == .unixStream
                    || connection.protocol == .unixDatagram
            }
        }
        let sorted = tabFiltered.sorted { lhs, rhs in
            if lhs.pid != rhs.pid { return lhs.pid < rhs.pid }
            return lhs.fd < rhs.fd
        }
        guard !searchText.isEmpty else { return sorted }
        let needle = searchText.lowercased()
        return sorted.filter { connection in
            let processName = processNames[connection.pid]?.lowercased() ?? ""
            return processName.contains(needle)
                || (connection.localAddress?.lowercased().contains(needle) ?? false)
                || (connection.remoteAddress?.lowercased().contains(needle) ?? false)
                || String(connection.localPort ?? 0).contains(needle)
                || String(connection.remotePort ?? 0).contains(needle)
                || String(connection.pid).contains(needle)
                || (connection.tcpState?.displayName.lowercased().contains(needle) ?? false)
        }
    }

    /// Counts per tab — drives the sidebar badges.
    func count(for tab: NetworkTab) -> Int {
        switch tab {
        case .all: return connections.count
        case .listeners: return connections.lazy.filter(\.isListener).count
        case .tcp: return connections.lazy.filter { $0.protocol == .tcp }.count
        case .udp: return connections.lazy.filter { $0.protocol == .udp }.count
        case .unix:
            return connections.lazy.filter {
                $0.protocol == .unixStream || $0.protocol == .unixDatagram
            }.count
        }
    }

    /// Currently-selected connection looked up by the (pid, fd) key.
    var selectedConnection: Connection? {
        guard let key = selectedKey else { return nil }
        return connections.first { connectionKey($0) == key }
    }

    /// Stable identifier per connection — (pid, fd) is unique within
    /// a snapshot.
    func connectionKey(_ connection: Connection) -> String {
        "\(connection.pid):\(connection.fd)"
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        async let connectionsTask = Task.detached {
            (try? OWNetwork.snapshot()) ?? []
        }.value
        async let processNamesTask = Task.detached { () -> [pid_t: String] in
            let processes = (try? OWProcess.all(includeArguments: false, includeOpenFiles: false)) ?? []
            return Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0.name) })
        }.value

        connections = await connectionsTask
        processNames = await processNamesTask
        lastRefresh = Date()

        if let key = selectedKey,
           !connections.contains(where: { connectionKey($0) == key }) {
            selectedKey = nil
        }
    }
}

/// Tabs in the Network window sidebar. The same five filter modes
/// `owlwatch netstat` exposes via flags.
enum NetworkTab: String, CaseIterable, Identifiable, Hashable {
    case all
    case listeners
    case tcp
    case udp
    case unix

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All Connections"
        case .listeners: return "Listeners"
        case .tcp: return "TCP"
        case .udp: return "UDP"
        case .unix: return "Unix-domain"
        }
    }

    var symbolName: String {
        switch self {
        case .all: return "network"
        case .listeners: return "antenna.radiowaves.left.and.right"
        case .tcp: return "arrow.left.arrow.right"
        case .udp: return "paperplane"
        case .unix: return "puzzlepiece"
        }
    }
}
