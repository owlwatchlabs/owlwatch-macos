import CoreAudio
import CoreMediaIO
import Foundation

extension OWDevices {
    /// Live-tail mic/camera in-use state. Returns an
    /// `AsyncThrowingStream` that yields one ``DeviceStateChange``
    /// per `IsRunningSomewhere` property transition (camera turns on,
    /// camera turns off, mic turns on, mic turns off).
    ///
    /// The monitor snapshots the device list at startup and registers
    /// CMIO + CoreAudio property listeners on each. Devices plugged in
    /// later are NOT picked up until the stream is recreated — the
    /// listener mechanism doesn't auto-extend to new devices. A
    /// future M11.x can also subscribe to
    /// `kCMIOHardwarePropertyDevices` / `kAudioHardwarePropertyDevices`
    /// to detect new attachments.
    ///
    /// Cancellation: the stream's `onTermination` callback removes
    /// every registered listener cleanly.
    public static func monitor() -> AsyncThrowingStream<DeviceStateChange, Error> {
        AsyncThrowingStream { continuation in
            let runner = DeviceMonitorRunner(continuation: continuation)
            do {
                try runner.start()
            } catch {
                continuation.finish(throwing: error)
                return
            }
            continuation.onTermination = { _ in
                runner.stop()
            }
        }
    }
}

/// Holds the device-listener registrations and yields state-change
/// events into the AsyncStream continuation.
///
/// Marked `@unchecked Sendable` because the CMIO / CoreAudio
/// property-listener callbacks fire on internal serial dispatch
/// queues — only one writer at a time touches the runner's state
/// (the queue keeps the invocations strictly ordered).
private final class DeviceMonitorRunner: @unchecked Sendable {
    private let continuation: AsyncThrowingStream<DeviceStateChange, Error>.Continuation
    private let queue = DispatchQueue(label: "com.owlwatchlabs.owlwatch.device-monitor")

    /// CMIO devices we registered listeners on, keyed by CMIODeviceID
    /// so we can deregister on stop. Includes the friendly name
    /// captured at startup so callbacks have it available without
    /// re-querying.
    private var cmioRegistrations: [CMIODeviceID: (uid: String, name: String)] = [:]

    /// CoreAudio devices we registered listeners on, keyed by
    /// AudioDeviceID.
    private var coreAudioRegistrations: [AudioDeviceID: (uid: String, name: String)] = [:]

    init(continuation: AsyncThrowingStream<DeviceStateChange, Error>.Continuation) {
        self.continuation = continuation
    }

    func start() throws {
        // Snapshot the cameras + microphones the user is paying for
        // detection on. Each becomes a property-listener registration.
        try registerCameraListeners()
        try registerMicrophoneListeners()
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.deregisterCameraListeners()
            self.deregisterMicrophoneListeners()
            self.continuation.finish()
        }
    }

    // MARK: - Camera listeners (CMIO)

    private func registerCameraListeners() throws {
        let cameras = OWDevices.cameras()
        let cmioMap = enumerateCMIODevicesByUID()

        for camera in cameras {
            guard let device = cmioMap[camera.id] else { continue }
            var addr = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            let context = Unmanaged.passUnretained(self).toOpaque()
            let status = CMIOObjectAddPropertyListener(device, &addr, { (_, _, _, info) in
                guard let info else { return 0 }
                let runner = Unmanaged<DeviceMonitorRunner>.fromOpaque(info).takeUnretainedValue()
                runner.handleCMIOPropertyChange(device: 0)  // device id re-queried below
                return 0
            }, context)
            guard status == 0 else {
                throw OWDevicesMonitorError.listenerRegistrationFailed(
                    uid: camera.id, status: status
                )
            }
            cmioRegistrations[device] = (camera.id, camera.name)
        }
    }

    private func deregisterCameraListeners() {
        for (device, _) in cmioRegistrations {
            var addr = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            let context = Unmanaged.passUnretained(self).toOpaque()
            _ = CMIOObjectRemovePropertyListener(device, &addr, { _, _, _, _ in 0 }, context)
        }
        cmioRegistrations.removeAll()
    }

    /// Re-scan every registered camera and yield a state-change event
    /// for whichever device just transitioned. The CMIO listener
    /// callback identifies *that the property changed* but not which
    /// element; rescanning all is cheap (handful of devices typically)
    /// and avoids guessing.
    func handleCMIOPropertyChange(device: CMIODeviceID) {
        for (device, info) in cmioRegistrations {
            let isInUse = readCMIODeviceIsRunningById(device)
            let change = DeviceStateChange(
                kind: .camera,
                id: info.uid,
                name: info.name,
                isInUse: isInUse,
                timestamp: Date()
            )
            continuation.yield(change)
        }
    }

    // MARK: - Microphone listeners (CoreAudio)

    private func registerMicrophoneListeners() throws {
        let mics = enumerateCoreAudioMicrophones()
        for mic in mics {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let context = Unmanaged.passUnretained(self).toOpaque()
            let status = AudioObjectAddPropertyListener(mic.id, &addr, { (_, _, _, info) in
                guard let info else { return 0 }
                let runner = Unmanaged<DeviceMonitorRunner>.fromOpaque(info).takeUnretainedValue()
                runner.handleCoreAudioPropertyChange()
                return 0
            }, context)
            guard status == 0 else {
                throw OWDevicesMonitorError.listenerRegistrationFailed(
                    uid: mic.uid, status: status
                )
            }
            coreAudioRegistrations[mic.id] = (mic.uid, mic.name)
        }
    }

    private func deregisterMicrophoneListeners() {
        for (device, _) in coreAudioRegistrations {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let context = Unmanaged.passUnretained(self).toOpaque()
            _ = AudioObjectRemovePropertyListener(device, &addr, { _, _, _, _ in 0 }, context)
        }
        coreAudioRegistrations.removeAll()
    }

    func handleCoreAudioPropertyChange() {
        for (device, info) in coreAudioRegistrations {
            let isInUse = readCoreAudioDeviceIsRunning(device)
            let change = DeviceStateChange(
                kind: .microphone,
                id: info.uid,
                name: info.name,
                isInUse: isInUse,
                timestamp: Date()
            )
            continuation.yield(change)
        }
    }
}

// MARK: - HAL helpers

/// Map every CMIO device to its UID for listener registration.
/// Internal twin of ``enumerateCMIOInUseStateByUID`` from M11.1 but
/// returning `[UID: CMIODeviceID]` instead of `[UID: Bool]`.
internal func enumerateCMIODevicesByUID() -> [String: CMIODeviceID] {
    var addr = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )
    let sysObject = CMIOObjectID(kCMIOObjectSystemObject)
    var listSize: UInt32 = 0
    guard CMIOObjectGetPropertyDataSize(sysObject, &addr, 0, nil, &listSize) == 0,
          listSize > 0 else {
        return [:]
    }
    let count = Int(listSize) / MemoryLayout<CMIODeviceID>.size
    var devices = [CMIODeviceID](repeating: 0, count: count)
    var got = listSize
    guard CMIOObjectGetPropertyData(sysObject, &addr, 0, nil, listSize, &got, &devices) == 0 else {
        return [:]
    }
    var result: [String: CMIODeviceID] = [:]
    for device in devices {
        if let uid = readCMIODeviceUIDForMonitor(device) {
            result[uid] = device
        }
    }
    return result
}

private func readCMIODeviceUIDForMonitor(_ device: CMIODeviceID) -> String? {
    var addr = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )
    var uid: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<CFString?>.size)
    let status = CMIOObjectGetPropertyData(device, &addr, 0, nil, size, &size, &uid)
    guard status == 0, let uid else { return nil }
    return uid.takeRetainedValue() as String
}

internal func readCMIODeviceIsRunningById(_ device: CMIODeviceID) -> Bool {
    var addr = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )
    var running: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard CMIOObjectGetPropertyData(device, &addr, 0, nil, size, &size, &running) == 0 else {
        return false
    }
    return running != 0
}

internal func readCoreAudioDeviceIsRunning(_ device: AudioDeviceID) -> Bool {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var running: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &running) == 0 else {
        return false
    }
    return running != 0
}
