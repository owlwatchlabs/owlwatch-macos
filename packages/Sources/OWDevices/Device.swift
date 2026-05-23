import Foundation

/// Top-level device categories ``OWDevices/OWDevices`` enumerates.
///
/// Cameras (CMIO) and microphones (CoreAudio HAL) sit on different
/// Apple frameworks but share the same shape of question: *"does this
/// device exist, and is something using it right now?"*. Both are
/// modeled as value types in this module so detection rules can
/// match on either uniformly.
public enum DeviceKind: String, Sendable, Equatable, Hashable, CaseIterable {
    case camera
    case microphone
}

/// A camera (CMIO device) attached to the system.
///
/// Built-in (FaceTime / MacBook camera), external (USB webcam, Apple
/// Studio Display), virtual (OBS Virtual Camera, Continuity Camera's
/// per-iPhone proxy), and Continuity Camera devices all surface
/// through the same struct. ``isVirtual`` and ``isExternal`` separate
/// them when detection rules care.
///
/// For an EDR, the security-relevant signals are:
///
/// - **`isInUse`** — *something* on the box has the camera open.
///   Apple's recording-light LED is the user-facing equivalent; this
///   is the programmatic answer. Pair with M6.2 TCC events to soft-
///   attribute to a process (M11.3 lands the full correlation).
/// - **`isVirtual`** — virtual cameras are a known malware/data-
///   exfiltration channel (recording the user's real camera then
///   re-broadcasting through a virtual device the attacker controls).
/// - **`isExternal`** — newly-plugged USB cameras are a phishing
///   surface (hostile device pretends to be a webcam, exfiltrates
///   audio via embedded microphone).
public struct Camera: Sendable, Equatable, Hashable {
    /// CMIO `kCMIODevicePropertyDeviceUID`. Stable across reboots
    /// for built-in devices; per-session for some external devices.
    public let id: String

    /// Human-readable name from `AVCaptureDevice.localizedName`.
    public let name: String

    /// `AVCaptureDevice.manufacturer`. `nil` when the device doesn't
    /// report one (rare).
    public let manufacturer: String?

    /// `AVCaptureDevice.modelID`. Apple's built-in cameras report a
    /// CMIO-formatted ID; external cameras typically report
    /// vendor:product IDs.
    public let modelID: String?

    /// `true` when CMIO reports `kCMIODevicePropertyDeviceIsRunningSomewhere`
    /// for this camera at the moment the snapshot was captured.
    public let isInUse: Bool

    /// `true` when the device is external (USB, Thunderbolt, network),
    /// `false` for built-in. Derived from
    /// `AVCaptureDevice.DiscoverySession`'s device type.
    public let isExternal: Bool

    /// `true` when the device is a virtual camera (OBS Virtual Camera,
    /// Continuity Camera proxy, etc.) rather than a hardware capture
    /// device.
    public let isVirtual: Bool

    public init(
        id: String,
        name: String,
        manufacturer: String?,
        modelID: String?,
        isInUse: Bool,
        isExternal: Bool,
        isVirtual: Bool
    ) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.modelID = modelID
        self.isInUse = isInUse
        self.isExternal = isExternal
        self.isVirtual = isVirtual
    }
}

/// A microphone (CoreAudio HAL audio input device) attached to the
/// system.
///
/// CoreAudio enumerates every audio interface — built-in mic, USB
/// audio interfaces, virtual audio devices like BlackHole / Loopback
/// / Audio Hijack. Output-only devices (speakers, headphones) are
/// excluded by checking `kAudioDevicePropertyStreamConfiguration` on
/// the input scope.
///
/// Same security framing as ``Camera``: ``isInUse`` is the
/// programmatic equivalent of the orange microphone indicator in the
/// macOS menu bar.
public struct Microphone: Sendable, Equatable, Hashable {
    /// CoreAudio `kAudioDevicePropertyDeviceUID`.
    public let id: String

    /// `AVCaptureDevice.localizedName` (preferred) or CoreAudio
    /// `kAudioObjectPropertyName` if AVCaptureDevice didn't enumerate
    /// the device.
    public let name: String

    /// Manufacturer reported by either AVCaptureDevice or CoreAudio.
    /// `nil` when neither knows.
    public let manufacturer: String?

    /// `true` when CoreAudio reports
    /// `kAudioDevicePropertyDeviceIsRunningSomewhere` for this device
    /// at snapshot time.
    public let isInUse: Bool

    /// `true` for USB / Thunderbolt / network audio interfaces;
    /// `false` for the built-in mic.
    public let isExternal: Bool

    public init(
        id: String,
        name: String,
        manufacturer: String?,
        isInUse: Bool,
        isExternal: Bool
    ) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.isInUse = isInUse
        self.isExternal = isExternal
    }
}
