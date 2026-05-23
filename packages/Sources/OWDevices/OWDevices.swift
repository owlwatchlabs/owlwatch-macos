import AVFoundation
import CoreAudio
import CoreMediaIO
import Foundation

/// Enumerate cameras and microphones attached to the system plus the
/// "is in use right now?" state for each.
///
/// Two data paths:
///
/// - **Cameras** — `AVCaptureDevice.DiscoverySession` for the friendly
///   metadata (name, manufacturer, model, built-in vs external), then
///   the underlying **CMIO HAL** (`CoreMediaIO` framework) for the
///   `kCMIODevicePropertyDeviceIsRunningSomewhere` "in use" bit.
/// - **Microphones** — `AVCaptureDevice` for friendly metadata where
///   available, **CoreAudio HAL** as the source of truth for the
///   device list and the `kAudioDevicePropertyDeviceIsRunningSomewhere`
///   "in use" bit.
///
/// What this module deliberately *cannot* tell you: which process is
/// using the device. macOS doesn't expose that through any public
/// API — it's a privacy boundary Apple has explicitly closed. M11.3
/// adds best-effort soft attribution by cross-referencing TCC events
/// (M6.2) and `com.apple.cmio` / `coreaudiod` log entries (M6.1).
public enum OWDevices {
    /// Capture every camera the system reports, plus the current
    /// "in use" state of each.
    public static func cameras() -> [Camera] {
        let avDevices = enumerateAVCameras()
        let cmioState = enumerateCMIOInUseStateByUID()

        return avDevices.map { av in
            Camera(
                id: av.uniqueID,
                name: av.localizedName,
                manufacturer: av.manufacturer.isEmpty ? nil : av.manufacturer,
                modelID: av.modelID.isEmpty ? nil : av.modelID,
                isInUse: cmioState[av.uniqueID] ?? false,
                isExternal: isExternalCamera(av),
                isVirtual: isVirtualCamera(av)
            )
        }
    }

    /// Capture every audio-input device CoreAudio reports, plus the
    /// current "in use" state of each.
    public static func microphones() -> [Microphone] {
        let coreAudioMics = enumerateCoreAudioMicrophones()
        let avMicsByUID = Dictionary(
            uniqueKeysWithValues: enumerateAVMicrophones().map { ($0.uniqueID, $0) }
        )

        return coreAudioMics.map { ca in
            let av = avMicsByUID[ca.uid]
            return Microphone(
                id: ca.uid,
                name: av?.localizedName ?? ca.name,
                manufacturer: av.flatMap { $0.manufacturer.isEmpty ? nil : $0.manufacturer }
                    ?? ca.manufacturer,
                isInUse: ca.isInUse,
                isExternal: ca.transportType != kAudioDeviceTransportTypeBuiltIn
            )
        }
    }
}

// MARK: - AVCaptureDevice enumeration

private func enumerateAVCameras() -> [AVCaptureDevice] {
    let session = AVCaptureDevice.DiscoverySession(
        deviceTypes: [
            .builtInWideAngleCamera,
            .continuityCamera,
            .deskViewCamera,
            .external
        ],
        mediaType: .video,
        position: .unspecified
    )
    return session.devices
}

private func enumerateAVMicrophones() -> [AVCaptureDevice] {
    let session = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.microphone, .external],
        mediaType: .audio,
        position: .unspecified
    )
    return session.devices
}

private func isExternalCamera(_ device: AVCaptureDevice) -> Bool {
    // The .external device type is the unambiguous external case.
    // Continuity Camera devices report .continuityCamera but are
    // physically external (iPhone over the network), so we also flag
    // them as external.
    device.deviceType == .external || device.deviceType == .continuityCamera
}

private func isVirtualCamera(_ device: AVCaptureDevice) -> Bool {
    // Continuity Camera and Desk View Camera are Apple's own virtual
    // devices that re-broadcast another physical camera. Third-party
    // virtual cameras (OBS, etc.) report `.external` with synthetic
    // model IDs — we don't have a reliable public way to flag those,
    // so this property reports Apple-virtual cameras only for now.
    device.deviceType == .continuityCamera || device.deviceType == .deskViewCamera
}

// MARK: - CMIO in-use enumeration

/// Walk every CMIO device the system exposes and return the
/// (UID → isInUse) map. Cameras whose UIDs don't appear here aren't
/// CMIO-managed (rare; usually a sign AVCaptureDevice and CMIO
/// disagree on what's present).
internal func enumerateCMIOInUseStateByUID() -> [String: Bool] {
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

    var result: [String: Bool] = [:]
    for device in devices {
        guard let uid = readCMIODeviceUID(device) else { continue }
        result[uid] = readCMIODeviceIsRunning(device)
    }
    return result
}

private func readCMIODeviceUID(_ device: CMIODeviceID) -> String? {
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

private func readCMIODeviceIsRunning(_ device: CMIODeviceID) -> Bool {
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

// MARK: - CoreAudio enumeration

internal struct CoreAudioMicrophone {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let manufacturer: String?
    let isInUse: Bool
    let transportType: UInt32
}

/// Walk every CoreAudio device on the system, filter to those that
/// have at least one input channel (i.e. capture devices), and read
/// their UID, name, manufacturer, transport type, and in-use bit.
internal func enumerateCoreAudioMicrophones() -> [CoreAudioMicrophone] {
    var listAddr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var listSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &listAddr, 0, nil, &listSize
    ) == 0, listSize > 0 else { return [] }

    let count = Int(listSize) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: count)
    var got = listSize
    guard AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &listAddr, 0, nil, &got, &devices
    ) == 0 else { return [] }

    var result: [CoreAudioMicrophone] = []
    for device in devices {
        guard deviceHasInputChannels(device) else { continue }
        let uid = readAudioDeviceProperty(
            device, selector: kAudioDevicePropertyDeviceUID
        ) ?? ""
        let name = readAudioDeviceProperty(
            device, selector: kAudioObjectPropertyName
        ) ?? "(unknown)"
        let manufacturer = readAudioDeviceProperty(
            device, selector: kAudioObjectPropertyManufacturer
        )
        let isInUse = readAudioDeviceIsRunning(device)
        let transport = readAudioDeviceTransportType(device)
        result.append(CoreAudioMicrophone(
            id: device,
            uid: uid,
            name: name,
            manufacturer: manufacturer,
            isInUse: isInUse,
            transportType: transport
        ))
    }
    return result
}

private func deviceHasInputChannels(_ device: AudioDeviceID) -> Bool {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == 0,
          size > 0 else { return false }
    let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(
        capacity: Int(size)
    )
    defer { bufferList.deallocate() }
    guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, bufferList) == 0 else {
        return false
    }
    let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
    let total = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    return total > 0
}

private func readAudioDeviceProperty(
    _ device: AudioDeviceID,
    selector: AudioObjectPropertySelector
) -> String? {
    var addr = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var stringRef: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = withUnsafeMutablePointer(to: &stringRef) { ptr in
        AudioObjectGetPropertyData(device, &addr, 0, nil, &size, ptr)
    }
    guard status == 0 else { return nil }
    let result = stringRef as String
    return result.isEmpty ? nil : result
}

private func readAudioDeviceIsRunning(_ device: AudioDeviceID) -> Bool {
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

private func readAudioDeviceTransportType(_ device: AudioDeviceID) -> UInt32 {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyTransportType,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var transport: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &transport) == 0 else {
        return 0
    }
    return transport
}
