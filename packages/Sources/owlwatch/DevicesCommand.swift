import ArgumentParser
import Foundation
import OWDevices

struct DevicesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "devices",
        abstract: "List cameras and microphones plus whether each is in use right now.",
        discussion: """
            Enumerates every camera (via CMIO HAL) and every audio-input \
            device (via CoreAudio HAL) attached to the system, with \
            friendly names from AVCaptureDevice and the \
            kCMIODevicePropertyDeviceIsRunningSomewhere / \
            kAudioDevicePropertyDeviceIsRunningSomewhere "in use" bit \
            for each.

            macOS does not expose which *process* is using a device — \
            that's a privacy boundary Apple has closed. Soft attribution \
            via TCC events and log correlation lands in M11.3.

            Output columns: TYPE, NAME, MANUFACTURER, IN USE, EXTERNAL, ID.

            Examples:
              owlwatch devices
              owlwatch devices --cameras
              owlwatch devices --microphones
              owlwatch devices --in-use-only
        """
    )

    @Flag(name: .long, help: "Only show cameras.")
    var cameras: Bool = false

    @Flag(name: .long, help: "Only show microphones.")
    var microphones: Bool = false

    @Flag(name: .long, help: "Only show devices currently in use.")
    var inUseOnly: Bool = false

    func run() throws {
        var rows: [[String]] = []

        if !microphones {
            for camera in OWDevices.cameras() {
                if inUseOnly && !camera.isInUse { continue }
                rows.append(renderCamera(camera))
            }
        }
        if !cameras {
            for mic in OWDevices.microphones() {
                if inUseOnly && !mic.isInUse { continue }
                rows.append(renderMicrophone(mic))
            }
        }

        if rows.isEmpty {
            if inUseOnly {
                print("(no devices currently in use)")
            } else {
                print("(no devices found)")
            }
            return
        }

        let header = ["TYPE", "NAME", "MANUFACTURER", "IN USE", "EXTERNAL", "ID"]
        let widths = columnWidths(header: header, rows: rows)
        print(formatRow(header, widths: widths))
        for row in rows {
            print(formatRow(row, widths: widths))
        }
    }

    private func renderCamera(_ camera: Camera) -> [String] {
        var typeLabel = "camera"
        if camera.isVirtual { typeLabel += " (virtual)" }
        return [
            typeLabel,
            camera.name,
            camera.manufacturer ?? "-",
            camera.isInUse ? "YES" : "no",
            camera.isExternal ? "yes" : "no",
            camera.id
        ]
    }

    private func renderMicrophone(_ mic: Microphone) -> [String] {
        [
            "microphone",
            mic.name,
            mic.manufacturer ?? "-",
            mic.isInUse ? "YES" : "no",
            mic.isExternal ? "yes" : "no",
            mic.id
        ]
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
