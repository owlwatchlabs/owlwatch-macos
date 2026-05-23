import Foundation
import OWDevices
import OWLog

/// Drives the M16.6 live menu-bar indicator. Tracks two pieces of
/// always-on status:
///
/// - **Devices in use** — cameras + microphones with `IsRunningSomewhere`
///   set. Refreshed from `OWDevices.cameras()` / `microphones()`
///   snapshots at startup and on every `OWDevices.monitor()` event.
/// - **Recent TCC denials** — count over the last 5 minutes, polled
///   from `OWLog.tccEvents()` on a 60-second timer. The unified-log
///   query is too slow for a tighter cadence (`log show` takes seconds
///   on a busy box).
///
/// The menu-bar icon and dropdown header observe this model and
/// re-render reactively. The model itself owns the long-running tasks
/// and tears them down on `stop()`.
@MainActor
@Observable
final class MenuBarStatusModel {
    // MARK: - Live state

    /// Number of cameras currently `IsRunningSomewhere`.
    var cameraInUseCount: Int = 0

    /// Number of microphones currently `IsRunningSomewhere`.
    var microphoneInUseCount: Int = 0

    /// Cameras + microphones combined.
    var devicesInUseCount: Int { cameraInUseCount + microphoneInUseCount }

    /// Denied TCC events in the last 5 minutes.
    var recentTCCDenialCount: Int = 0

    /// When the device snapshot or TCC poll last ran. Surfaced to the
    /// dropdown so the user can tell the indicator is current.
    var lastUpdated: Date?

    /// Last error from the monitor stream — surfaced in the dropdown
    /// header in muted text when present.
    var lastError: String?

    // MARK: - Tasks

    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var tccPollerTask: Task<Void, Never>?

    // MARK: - Lifecycle

    /// Start the long-running tasks. Idempotent — calling twice is a
    /// no-op so the App's `.task { }` modifier is safe to use.
    func start() {
        guard monitorTask == nil else { return }

        Task { await refreshDeviceSnapshot() }

        monitorTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await change in OWDevices.monitor() {
                    if Task.isCancelled { return }
                    await self.handle(change: change)
                }
            } catch {
                await MainActor.run { self.lastError = "Device monitor failed: \(error)" }
            }
        }

        tccPollerTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshTCCDenials()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// Cancel the monitor + poller. The continuation's `onTermination`
    /// in `OWDevices.monitor()` cleans up the CMIO / CoreAudio
    /// listeners.
    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        tccPollerTask?.cancel()
        tccPollerTask = nil
    }

    // MARK: - Refresh

    private func refreshDeviceSnapshot() async {
        let cams = await Task.detached { OWDevices.cameras() }.value
        let mics = await Task.detached { OWDevices.microphones() }.value
        cameraInUseCount = cams.filter { $0.isInUse }.count
        microphoneInUseCount = mics.filter { $0.isInUse }.count
        lastUpdated = Date()
    }

    /// Apply one stream event. We could update the in-use count
    /// directly from `change.isInUse` but two devices can race; a full
    /// re-snapshot stays in sync at trivial cost (cameras() /
    /// microphones() are sub-millisecond).
    private func handle(change: DeviceStateChange) async {
        await refreshDeviceSnapshot()
    }

    private func refreshTCCDenials() async {
        var query = LogQuery.tccDefault
        query.since = Date().addingTimeInterval(-300)
        let count = await Task.detached { () -> Int in
            guard let events = try? OWLog.tccEvents(query) else { return 0 }
            return events.filter { $0.outcome == .denied }.count
        }.value
        recentTCCDenialCount = count
        lastUpdated = Date()
    }
}
