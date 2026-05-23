import Darwin
import Foundation

/// A single Transparency, Consent and Control (TCC) decision —
/// reconstructed from the 6-line transaction macOS emits to
/// `com.apple.TCC`/`access` for every privacy-permission request.
///
/// TCC is the macOS framework that gates camera, microphone,
/// accessibility, screen capture, full disk access, Apple Events
/// automation, contacts, calendar, location, and the protected
/// user-folder categories. Every request — granted or denied,
/// preflight or real — produces a log transaction.
///
/// For an EDR, TCC events are tier-1 signal:
///
/// - **Repeated denials** from the same process suggest probing or
///   misconfiguration; spike in denials suggests intrusion.
/// - **Grants to unsigned / unexpected binaries** suggest the user
///   was social-engineered into approving an unwanted permission.
/// - **Accessing-process / requesting-process divergence** (e.g.
///   ContinuityCaptureAgent requesting on behalf of WhatsApp)
///   surfaces delegation chains that detection rules need to follow.
///
/// Transactions are correlated by ``msgID``; lines that arrive
/// without a corresponding context line (the ``AUTHREQ_CTX`` line
/// carrying `service=...`) are dropped, since without the service
/// the event has no detection value.
public struct TCCEvent: Sendable, Equatable, Hashable {
    /// Timestamp from the earliest log entry in the transaction
    /// (the `REQUEST` line, or the next available line if `REQUEST`
    /// is missing from the snapshot window).
    public let timestamp: Date

    /// `tccd`-internal transaction identifier — formatted as
    /// `<tccd_pid>.<sequence>`, e.g. `404.34234`. Stable across the
    /// 6 lines that make up one TCC transaction.
    public let msgID: String

    /// The TCC service being requested (camera, mic, FDA, ...).
    /// `.other(rawValue:)` carries the raw `kTCCService*` string
    /// when we don't recognize it.
    public let service: TCCService

    /// `true` when the request was a "preflight" — *would this be
    /// allowed?* — rather than an actual access attempt. Preflights
    /// don't trigger user prompts and don't get logged in TCC's
    /// access database.
    public let isPreflight: Bool

    /// The process actually receiving the requested permission
    /// (the app/binary the user sees). Often differs from
    /// ``requestingProcess`` because Apple's frameworks broker
    /// many permissions through intermediary daemons.
    public let accessingProcess: TCCProcessRef?

    /// The process making the request — the daemon or intermediary
    /// the framework speaks to. For direct requests this equals
    /// ``accessingProcess``.
    public let requestingProcess: TCCProcessRef?

    /// Classified outcome derived from `AUTHREQ_RESULT.authValue`.
    /// See ``TCCOutcome``.
    public let outcome: TCCOutcome

    /// Raw `authValue` integer for callers that need to match on
    /// values our enum doesn't classify.
    public let authValueRaw: Int

    /// Raw `authReason` integer — internal tccd reason code for
    /// the outcome.
    public let authReasonRaw: Int

    public init(
        timestamp: Date,
        msgID: String,
        service: TCCService,
        isPreflight: Bool,
        accessingProcess: TCCProcessRef?,
        requestingProcess: TCCProcessRef?,
        outcome: TCCOutcome,
        authValueRaw: Int,
        authReasonRaw: Int
    ) {
        self.timestamp = timestamp
        self.msgID = msgID
        self.service = service
        self.isPreflight = isPreflight
        self.accessingProcess = accessingProcess
        self.requestingProcess = requestingProcess
        self.outcome = outcome
        self.authValueRaw = authValueRaw
        self.authReasonRaw = authReasonRaw
    }

    /// `true` when the same process appears as both ``accessingProcess``
    /// and ``requestingProcess``. False indicates a brokered
    /// permission — the requesting daemon is asking on behalf of a
    /// distinct app.
    public var isDirectRequest: Bool {
        guard let accessing = accessingProcess, let requesting = requestingProcess else {
            return false
        }
        return accessing.identifier == requesting.identifier
    }
}

/// A process referenced inside a TCC `AUTHREQ_ATTRIBUTION` line.
/// Comes from the `TCCDProcess: identifier=..., pid=..., auid=...,
/// euid=..., binary_path=...` blocks.
public struct TCCProcessRef: Sendable, Equatable, Hashable {
    /// Bundle / signing identifier — `net.whatsapp.WhatsApp`,
    /// `com.apple.cmio.ContinuityCaptureAgent`, etc.
    public let identifier: String

    /// Process ID at the time the request was logged.
    public let pid: pid_t

    /// Audit UID — the original user identity, preserved across
    /// `setuid` transitions.
    public let auid: uid_t

    /// Effective UID at the time of the request.
    public let euid: uid_t

    /// Filesystem path to the binary. Cross-reference with
    /// ``OWCodeSigning`` to check signing status of the requester.
    public let binaryPath: String

    public init(
        identifier: String,
        pid: pid_t,
        auid: uid_t,
        euid: uid_t,
        binaryPath: String
    ) {
        self.identifier = identifier
        self.pid = pid
        self.auid = auid
        self.euid = euid
        self.binaryPath = binaryPath
    }
}

/// The macOS TCC service catalog — what permission was requested.
///
/// Raw values are the canonical `kTCCService*` strings tccd emits.
/// New services Apple adds (Vision Pro permissions, Apple Intelligence
/// gates) land in ``other(rawValue:)`` with the raw string preserved
/// so detection rules can still match.
public enum TCCService: Sendable, Equatable, Hashable {
    case accessibility           // kTCCServiceAccessibility
    case addressBook             // kTCCServiceAddressBook
    case appleEvents             // kTCCServiceAppleEvents (Automation)
    case bluetoothAlways         // kTCCServiceBluetoothAlways
    case calendar                // kTCCServiceCalendar
    case camera                  // kTCCServiceCamera
    case contactsFull            // kTCCServiceContactsFull
    case contactsLimited         // kTCCServiceContactsLimited
    case desktopFolder           // kTCCServiceSystemPolicyDesktopFolder
    case developerTool           // kTCCServiceDeveloperTool
    case documentsFolder         // kTCCServiceSystemPolicyDocumentsFolder
    case downloadsFolder         // kTCCServiceSystemPolicyDownloadsFolder
    case fileProviderDomain      // kTCCServiceFileProviderDomain
    case fullDiskAccess          // kTCCServiceSystemPolicyAllFiles
    case inputMonitoring         // kTCCServiceListenEvent
    case location                // kTCCServiceLocation
    case mediaLibrary            // kTCCServiceMediaLibrary
    case microphone              // kTCCServiceMicrophone
    case networkVolumes          // kTCCServiceSystemPolicyNetworkVolumes
    case photos                  // kTCCServicePhotos
    case postEvent               // kTCCServicePostEvent
    case reminders               // kTCCServiceReminders
    case removableVolumes        // kTCCServiceSystemPolicyRemovableVolumes
    case screenCapture           // kTCCServiceScreenCapture
    case speechRecognition       // kTCCServiceSpeechRecognition
    case userTracking            // kTCCServiceUserTracking
    case other(rawValue: String)

    public var rawValue: String {
        switch self {
        case .accessibility: return "kTCCServiceAccessibility"
        case .addressBook: return "kTCCServiceAddressBook"
        case .appleEvents: return "kTCCServiceAppleEvents"
        case .bluetoothAlways: return "kTCCServiceBluetoothAlways"
        case .calendar: return "kTCCServiceCalendar"
        case .camera: return "kTCCServiceCamera"
        case .contactsFull: return "kTCCServiceContactsFull"
        case .contactsLimited: return "kTCCServiceContactsLimited"
        case .desktopFolder: return "kTCCServiceSystemPolicyDesktopFolder"
        case .developerTool: return "kTCCServiceDeveloperTool"
        case .documentsFolder: return "kTCCServiceSystemPolicyDocumentsFolder"
        case .downloadsFolder: return "kTCCServiceSystemPolicyDownloadsFolder"
        case .fileProviderDomain: return "kTCCServiceFileProviderDomain"
        case .fullDiskAccess: return "kTCCServiceSystemPolicyAllFiles"
        case .inputMonitoring: return "kTCCServiceListenEvent"
        case .location: return "kTCCServiceLocation"
        case .mediaLibrary: return "kTCCServiceMediaLibrary"
        case .microphone: return "kTCCServiceMicrophone"
        case .networkVolumes: return "kTCCServiceSystemPolicyNetworkVolumes"
        case .photos: return "kTCCServicePhotos"
        case .postEvent: return "kTCCServicePostEvent"
        case .reminders: return "kTCCServiceReminders"
        case .removableVolumes: return "kTCCServiceSystemPolicyRemovableVolumes"
        case .screenCapture: return "kTCCServiceScreenCapture"
        case .speechRecognition: return "kTCCServiceSpeechRecognition"
        case .userTracking: return "kTCCServiceUserTracking"
        case .other(let raw): return raw
        }
    }

    /// Map from the raw `kTCCService*` string `tccd` emits.
    public static func from(rawValue: String) -> TCCService {
        rawValueLookup[rawValue] ?? .other(rawValue: rawValue)
    }

    /// Lookup table for the recognized `kTCCService*` strings. Kept as
    /// a static map rather than a switch so we can extend it without
    /// hitting SwiftLint's cyclomatic-complexity ceiling.
    private static let rawValueLookup: [String: TCCService] = [
        "kTCCServiceAccessibility": .accessibility,
        "kTCCServiceAddressBook": .addressBook,
        "kTCCServiceAppleEvents": .appleEvents,
        "kTCCServiceBluetoothAlways": .bluetoothAlways,
        "kTCCServiceCalendar": .calendar,
        "kTCCServiceCamera": .camera,
        "kTCCServiceContactsFull": .contactsFull,
        "kTCCServiceContactsLimited": .contactsLimited,
        "kTCCServiceSystemPolicyDesktopFolder": .desktopFolder,
        "kTCCServiceDeveloperTool": .developerTool,
        "kTCCServiceSystemPolicyDocumentsFolder": .documentsFolder,
        "kTCCServiceSystemPolicyDownloadsFolder": .downloadsFolder,
        "kTCCServiceFileProviderDomain": .fileProviderDomain,
        "kTCCServiceSystemPolicyAllFiles": .fullDiskAccess,
        "kTCCServiceListenEvent": .inputMonitoring,
        "kTCCServiceLocation": .location,
        "kTCCServiceMediaLibrary": .mediaLibrary,
        "kTCCServiceMicrophone": .microphone,
        "kTCCServiceSystemPolicyNetworkVolumes": .networkVolumes,
        "kTCCServicePhotos": .photos,
        "kTCCServicePostEvent": .postEvent,
        "kTCCServiceReminders": .reminders,
        "kTCCServiceSystemPolicyRemovableVolumes": .removableVolumes,
        "kTCCServiceScreenCapture": .screenCapture,
        "kTCCServiceSpeechRecognition": .speechRecognition,
        "kTCCServiceUserTracking": .userTracking
    ]
}

/// Classified TCC outcome. Derived from `AUTHREQ_RESULT.authValue`.
///
/// Apple does not publicly document the full `authValue` enumeration;
/// the values below are what's been reverse-engineered and is stable
/// across multiple macOS releases. Anything else lands in
/// ``unknown(rawValue:)`` so detection rules can still match.
public enum TCCOutcome: Sendable, Equatable, Hashable {
    /// `authValue == 0` — request denied.
    case denied

    /// `authValue == 2` — request allowed.
    case allowed

    /// `authValue == 3` — allowed but with a limited grant (e.g.
    /// Limited Photos access).
    case allowedLimited

    /// Any other observed value. Raw integer preserved.
    case unknown(rawValue: Int)

    public static func from(authValue: Int) -> TCCOutcome {
        switch authValue {
        case 0: return .denied
        case 2: return .allowed
        case 3: return .allowedLimited
        default: return .unknown(rawValue: authValue)
        }
    }

    /// Stable lowercase rendering for display.
    public var displayName: String {
        switch self {
        case .denied: return "denied"
        case .allowed: return "allowed"
        case .allowedLimited: return "allowed-limited"
        case .unknown(let raw): return "unknown(\(raw))"
        }
    }
}
