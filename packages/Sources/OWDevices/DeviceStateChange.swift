import Foundation

/// A single mic/camera in-use transition observed by the
/// ``OWDevices/OWDevices/monitor()`` live stream.
///
/// `DeviceStateChange` is the M11.2 live counterpart to M11.1's
/// snapshot: where ``OWDevices/OWDevices/cameras()`` and
/// ``microphones()`` answer *"which devices exist and are any in
/// use right now?"*, the monitor stream answers *"which device just
/// transitioned, and to what state?"*.
///
/// One record per transition. The kernel's CMIO / CoreAudio
/// property-listener mechanism only fires when
/// `kCMIODevicePropertyDeviceIsRunningSomewhere` /
/// `kAudioDevicePropertyDeviceIsRunningSomewhere` flips — so the
/// stream is naturally edge-triggered and quiet between events.
///
/// For an EDR, the events of interest are:
///
/// - **Camera transitioning to in-use unexpectedly** — Apple's
///   recording-light LED is the user-facing equivalent. This event
///   is the programmatic trigger for "alert if camera went on while
///   the lid was closed / the user was away from keyboard / no
///   foreground app has TCC permission".
/// - **Microphone in-use without a corresponding camera** — common
///   in audio-only eavesdropping malware that doesn't want to trip
///   the camera light.
public struct DeviceStateChange: Sendable, Equatable, Hashable {
    /// Which kind of device this transition refers to.
    public let kind: DeviceKind

    /// Device identifier — CMIO `kCMIODevicePropertyDeviceUID` for
    /// cameras or CoreAudio `kAudioDevicePropertyDeviceUID` for
    /// microphones. Stable per-session; matches the `id` field of
    /// the corresponding ``Camera`` / ``Microphone`` snapshot record.
    public let id: String

    /// Friendly name from ``Camera/name`` / ``Microphone/name``.
    public let name: String

    /// New state — `true` means *just turned on*, `false` means
    /// *just turned off*.
    public let isInUse: Bool

    /// Wall-clock time the property-listener callback fired
    /// (typically within milliseconds of the kernel-level event).
    public let timestamp: Date

    public init(
        kind: DeviceKind,
        id: String,
        name: String,
        isInUse: Bool,
        timestamp: Date
    ) {
        self.kind = kind
        self.id = id
        self.name = name
        self.isInUse = isInUse
        self.timestamp = timestamp
    }
}

/// Errors thrown by ``OWDevices/OWDevices/monitor()``.
public enum OWDevicesMonitorError: Error, Sendable, Equatable {
    /// `CMIOObjectAddPropertyListener` or `AudioObjectAddPropertyListener`
    /// returned a non-zero OSStatus for one of the devices in the
    /// watch set. The failing device's UID is preserved.
    case listenerRegistrationFailed(uid: String, status: OSStatus)
}
