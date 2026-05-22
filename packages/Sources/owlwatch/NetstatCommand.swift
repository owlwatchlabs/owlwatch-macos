import ArgumentParser
import Darwin
import Foundation
import OWNetwork
import OWProcess

struct NetstatCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "netstat",
        abstract: "List open IP sockets attributed to the process holding them.",
        discussion: """
            Walks every visible process via libproc and prints one row per \
            open IP socket: protocol, local endpoint, remote endpoint, TCP \
            state (if applicable), and the owning PID + process name. \
            Same data source as `lsof -i`, same posture as `owlwatch ps` — \
            unprivileged callers see their own processes' sockets; root \
            sees everything.

            Examples:
              owlwatch netstat
              owlwatch netstat --listen
              owlwatch netstat --tcp --port 443
              owlwatch netstat --pid 1234
            """
    )

    @Flag(name: .shortAndLong, help: "Only show listening sockets (TCP LISTEN or bound UDP).")
    var listen: Bool = false

    @Flag(name: .shortAndLong, help: "Only show TCP sockets.")
    var tcp: Bool = false

    @Flag(name: .shortAndLong, help: "Only show UDP sockets.")
    var udp: Bool = false

    @Flag(name: .long, help: "Only show IPv4 sockets.")
    var ipv4: Bool = false

    @Flag(name: .long, help: "Only show IPv6 sockets.")
    var ipv6: Bool = false

    @Option(name: .long, help: "Filter by local or remote port.")
    var port: UInt16?

    @Option(name: .long, help: "Filter to one process by PID.")
    var pid: pid_t?

    func run() throws {
        let connections = try fetchConnections()
        let filtered = applyFilters(to: connections)
        let processNames = lookupProcessNames(for: filtered)
        printTable(connections: filtered, processNames: processNames)
    }

    private func fetchConnections() throws -> [Connection] {
        if let targetPid = pid {
            return try OWNetwork.snapshot(pid: targetPid)
        }
        return try OWNetwork.snapshot()
    }

    private func applyFilters(to connections: [Connection]) -> [Connection] {
        connections.filter { connection in
            if listen && !connection.isListener { return false }
            if tcp && connection.protocol != .tcp { return false }
            if udp && connection.protocol != .udp { return false }
            if ipv4 && connection.family != .ipv4 { return false }
            if ipv6 && connection.family != .ipv6 { return false }
            if let port {
                if connection.localPort != port && connection.remotePort != port {
                    return false
                }
            }
            return true
        }
    }

    private func lookupProcessNames(for connections: [Connection]) -> [pid_t: String] {
        let pids = Set(connections.map(\.pid))
        var names: [pid_t: String] = [:]
        for pid in pids {
            if let process = try? OWProcess.snapshot(pid: pid) {
                names[pid] = process.name
            }
        }
        return names
    }

    private func printTable(connections: [Connection], processNames: [pid_t: String]) {
        let sorted = connections.sorted { lhs, rhs in
            if lhs.pid != rhs.pid { return lhs.pid < rhs.pid }
            return lhs.fd < rhs.fd
        }
        let rows = sorted.map { renderRow($0, name: processNames[$0.pid] ?? "?") }
        let header = ["PROTO", "LOCAL", "REMOTE", "STATE", "PID", "PROCESS"]
        let widths = columnWidths(header: header, rows: rows)
        print(formatRow(header, widths: widths))
        for row in rows {
            print(formatRow(row, widths: widths))
        }
    }

    private func renderRow(_ connection: Connection, name: String) -> [String] {
        let proto = "\(connection.protocol.rawValue)\(connection.family == .ipv4 ? "4" : "6")"
        let localEndpoint = endpoint(address: connection.localAddress, port: connection.localPort)
        let remoteEndpoint = endpoint(address: connection.remoteAddress, port: connection.remotePort)
        let state = connection.tcpState?.displayName ?? "-"
        return [proto, localEndpoint, remoteEndpoint, state, String(connection.pid), name]
    }

    private func endpoint(address: String?, port: UInt16?) -> String {
        let host: String
        if let address {
            host = address.contains(":") ? "[\(address)]" : address
        } else {
            host = "*"
        }
        let portText = port.map(String.init) ?? "*"
        return "\(host):\(portText)"
    }

    private func columnWidths(header: [String], rows: [[String]]) -> [Int] {
        var widths = header.map { $0.count }
        for row in rows {
            for (index, cell) in row.enumerated() where index < widths.count {
                widths[index] = max(widths[index], cell.count)
            }
        }
        return widths
    }

    private func formatRow(_ cells: [String], widths: [Int]) -> String {
        cells.enumerated()
            .map { index, cell in cell.padding(toLength: widths[index], withPad: " ", startingAt: 0) }
            .joined(separator: "  ")
            .trimmingCharacters(in: .whitespaces)
    }
}
