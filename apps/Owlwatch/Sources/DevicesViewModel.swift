import Foundation
import OWDevices

/// Drives the M11.4 Devices window. Holds the camera + microphone
/// snapshot (M11.1), the live state-change history (M11.2), and the
/// UI state (selection, scope filter).
///
/// Snapshot fetches are fast (CMIO + CoreAudio HAL walks are
/// near-instant), so they run on the main actor with no `Task.detached`
/// hop. The live monitor runs as a long-lived task started in
/// ``startMonitor()`` and cancelled in ``stopMonitor()``.
@MainActor
@Observable
final class DevicesViewModel {
    /// Cap on retained state-change history. Idle systems emit a few
    /// events a day; an active call can fire several per second
    /// (transitions during reconnects). 500 covers heavy days.
    static let historyCap = 500

    var cameras: [Camera] = []
    var microphones: [Microphone] = []

    /// Live state-change history, newest-first.
    var events: [DeviceStateChange] = []

    /// Last successful snapshot timestamp — drives the toolbar refresh
    /// label.
    var lastRefresh: Date?

    /// Active sidebar tab.
    var selectedKind: DeviceSidebarKind = .cameras {
        didSet {
            if selectedKind == .events {
                unseenEventCount = 0
            }
        }
    }

    /// Event-tab unseen badge counter. Increments per yielded event
    /// unless the user is already looking at the Events tab.
    var unseenEventCount: Int = 0

    /// Selected device ID (camera UID or mic UID) or event ID (we
    /// synthesize an id per event from kind+UID+timestamp).
    var selectedItemID: String?

    @ObservationIgnored private var monitorTask: Task<Void, Never>?

    /// Triggered count for cameras currently in use — drives the
    /// sidebar badge for the Cameras tab.
    var camerasInUseCount: Int {
        cameras.lazy.filter(\.isInUse).count
    }

    /// Same for microphones.
    var microphonesInUseCount: Int {
        microphones.lazy.filter(\.isInUse).count
    }

    func refresh() {
        cameras = OWDevices.cameras()
        microphones = OWDevices.microphones()
        lastRefresh = Date()
    }

    func startMonitor() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await change in OWDevices.monitor() {
                    if Task.isCancelled { return }
                    self.appendEvent(change)
                }
            } catch {
                NSLog("OWDevices monitor failed: %@", "\(error)")
            }
        }
    }

    func stopMonitor() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func appendEvent(_ change: DeviceStateChange) {
        events.insert(change, at: 0)
        if events.count > Self.historyCap {
            events.removeLast(events.count - Self.historyCap)
        }
        // Refresh the snapshot in-place so the Cameras / Mics tabs
        // reflect the new in-use state without waiting for a manual
        // refresh.
        switch change.kind {
        case .camera:
            cameras = cameras.map {
                $0.id == change.id
                    ? Camera(id: $0.id, name: $0.name, manufacturer: $0.manufacturer,
                             modelID: $0.modelID, isInUse: change.isInUse,
                             isExternal: $0.isExternal, isVirtual: $0.isVirtual)
                    : $0
            }
        case .microphone:
            microphones = microphones.map {
                $0.id == change.id
                    ? Microphone(id: $0.id, name: $0.name, manufacturer: $0.manufacturer,
                                 isInUse: change.isInUse, isExternal: $0.isExternal)
                    : $0
            }
        }
        if selectedKind != .events {
            unseenEventCount += 1
        }
    }
}

/// Three views the Devices window sidebar offers.
enum DeviceSidebarKind: String, CaseIterable, Identifiable, Hashable {
    case cameras
    case microphones
    case events

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cameras: return "Cameras"
        case .microphones: return "Microphones"
        case .events: return "Live Events"
        }
    }

    var symbolName: String {
        switch self {
        case .cameras: return "camera"
        case .microphones: return "mic"
        case .events: return "dot.radiowaves.left.and.right"
        }
    }
}
