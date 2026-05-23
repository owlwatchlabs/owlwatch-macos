import ArgumentParser
import Darwin
import Foundation
import OWDevices

struct WatchDevicesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch-devices",
        abstract: "Live-tail camera and microphone in-use transitions.",
        discussion: """
            Subscribes to CMIO + CoreAudio property listeners on every \
            camera and microphone present at startup; prints one row \
            per state transition (camera turns on / off, mic turns on \
            / off). Runs until interrupted with Ctrl-C.

            Devices plugged in after this command starts are NOT \
            monitored — re-run the command to pick them up.

            Output columns: TIMESTAMP, KIND, STATE, NAME, ID.

            Examples:
              owlwatch watch-devices
              owlwatch watch-devices --kind camera
              owlwatch watch-devices --on-only
        """
    )

    @Option(name: .long, help: "Filter to one kind: camera or microphone.")
    var kind: String?

    @Flag(name: .long, help: "Only show transitions to in-use; ignore turns-off.")
    var onOnly: Bool = false

    func run() async throws {
        let allowedKind = parseKind(kind)

        let header = ["TIMESTAMP", "KIND", "STATE", "NAME", "ID"]
        let widths = [12, 10, 8, 40, 50]
        print(formatRow(header, widths: widths))
        fflush(stdout)

        for try await change in OWDevices.monitor() {
            if let allowedKind, change.kind != allowedKind { continue }
            if onOnly && !change.isInUse { continue }
            print(formatRow(renderRow(change), widths: widths))
            fflush(stdout)
        }
    }

    private func parseKind(_ string: String?) -> DeviceKind? {
        switch string {
        case "camera": return .camera
        case "microphone", "mic": return .microphone
        default: return nil
        }
    }

    private func renderRow(_ change: DeviceStateChange) -> [String] {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return [
            formatter.string(from: change.timestamp),
            change.kind.rawValue,
            change.isInUse ? "ON" : "off",
            change.name,
            change.id
        ]
    }

    private func formatRow(_ cells: [String], widths: [Int]) -> String {
        cells.enumerated()
            .map { index, cell in cell.padding(toLength: widths[index], withPad: " ", startingAt: 0) }
            .joined(separator: "  ")
            .trimmingCharacters(in: .whitespaces)
    }
}
