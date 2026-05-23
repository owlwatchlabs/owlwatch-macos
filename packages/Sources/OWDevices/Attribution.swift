import AppKit
import Darwin
import Foundation
import OWLog

/// A best-effort guess at which process triggered a
/// ``DeviceStateChange``.
///
/// macOS does not expose, through any public API, which process is
/// holding a camera or microphone — Apple has explicitly closed that
/// privacy boundary. ``OWDevices/OWDevices/attribute(_:lookbackSeconds:)``
/// works around this by cross-referencing two independent signals:
///
/// 1. **Recent TCC grants** — when a process opens a camera or
///    microphone, macOS's TCC daemon emits a 6-line transaction to
///    the unified log (see M6.2). The transaction names the
///    `accessingProcess` and the requested `service` (camera / mic).
///    If a `kTCCServiceCamera` / `kTCCServiceMicrophone` request
///    fired within `lookbackSeconds` before our device-state event,
///    the accessing process is a strong candidate.
/// 2. **Foreground application** — the currently-frontmost app
///    (from `NSWorkspace.shared.frontmostApplication`) is a weaker
///    candidate. Common case: a user starts a FaceTime call; FaceTime
///    is frontmost; mic opens. Not always reliable — background
///    processes can open the mic without becoming frontmost.
///
/// ``confidence`` reflects how strong the evidence is.
/// ``high`` means TCC fired recently with a matching service and
/// the user-visible foreground app matches it. ``medium`` means one
/// of those signals fired alone. ``low`` means we only have the
/// foreground app (no recent TCC) and the device just turned on.
public struct ProcessCandidate: Sendable, Equatable, Hashable {
    /// Bundle identifier or process name. Whatever the source gave us
    /// — TCC reports a `bundleIdentifier`, NSWorkspace gives a bundle
    /// identifier too. `nil` only if neither source supplied one.
    public let identifier: String?

    /// Process ID at the time the attribution ran. `nil` when only
    /// NSWorkspace surfaced a candidate (it reports bundle ID but
    /// always has a PID; this is just defensive).
    public let pid: pid_t?

    /// Which signal contributed this candidate.
    public let source: AttributionSource

    /// How strong the evidence is.
    public let confidence: AttributionConfidence

    /// Human-readable explanation of why this candidate was chosen.
    /// Helps detection-rule writers explain "why did Owlwatch flag X?".
    public let evidence: String

    public init(
        identifier: String?,
        pid: pid_t?,
        source: AttributionSource,
        confidence: AttributionConfidence,
        evidence: String
    ) {
        self.identifier = identifier
        self.pid = pid
        self.source = source
        self.confidence = confidence
        self.evidence = evidence
    }
}

/// Which independent signal produced an attribution candidate.
public enum AttributionSource: String, Sendable, Equatable, Hashable, CaseIterable {
    /// A `com.apple.TCC/access` log transaction fired with the
    /// matching service within the lookback window.
    case tccRecentRequest

    /// `NSWorkspace.shared.frontmostApplication` at attribution time.
    case foregroundApplication
}

/// Confidence rating for an attribution candidate.
public enum AttributionConfidence: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Multiple corroborating signals (TCC fired + foreground matches),
    /// or a single very-strong signal (TCC `.allowed` outcome within
    /// the last second).
    case high

    /// One signal with reasonable timing — e.g. TCC fired a few
    /// seconds ago, or the foreground app has the matching TCC
    /// permission.
    case medium

    /// Only weak evidence — e.g. foreground app at the time of the
    /// event, no TCC trail.
    case low
}

extension OWDevices {
    /// Best-effort attribute a device state transition to a process.
    ///
    /// Returns an ordered list of candidates, highest-confidence
    /// first. Empty array when no signal matched — the device opened,
    /// but neither TCC nor the foreground app pointed at a plausible
    /// consumer (rare; can happen for background daemons holding a
    /// long-standing TCC grant).
    ///
    /// `change.isInUse == false` (the device just *turned off*) is a
    /// less interesting event to attribute — the consumer might have
    /// already exited. This method still runs the same query, but
    /// callers can choose to skip attribution for off-transitions.
    public static func attribute(
        _ change: DeviceStateChange,
        lookbackSeconds: TimeInterval = 10.0
    ) -> [ProcessCandidate] {
        guard let service = serviceForKind(change.kind) else { return [] }

        var candidates: [ProcessCandidate] = []

        // TCC source — query the unified log for the relevant service.
        let tccCandidates = candidatesFromRecentTCCRequests(
            service: service,
            referenceTime: change.timestamp,
            lookbackSeconds: lookbackSeconds
        )
        candidates.append(contentsOf: tccCandidates)

        // Foreground app source — independent signal.
        if let foreground = candidateFromForegroundApplication(
            tccCandidates: tccCandidates
        ) {
            candidates.append(foreground)
        }

        // Stable ordering: high → medium → low. Within a confidence
        // tier, preserve insertion order (TCC first, foreground second).
        return candidates.sorted { lhs, rhs in
            confidenceRank(lhs.confidence) < confidenceRank(rhs.confidence)
        }
    }
}

// MARK: - TCC attribution

/// Map a ``DeviceKind`` to the matching `kTCCService*` string.
/// `nil` for kinds without a TCC equivalent (none today, but the
/// guard keeps callers explicit).
private func serviceForKind(_ kind: DeviceKind) -> String? {
    switch kind {
    case .camera: return "kTCCServiceCamera"
    case .microphone: return "kTCCServiceMicrophone"
    }
}

/// Look back through M6.2's typed TCC events for any request matching
/// the device's service. Recent + allowed → high confidence; recent +
/// any outcome → medium. Returns one candidate per matching unique
/// accessing process.
private func candidatesFromRecentTCCRequests(
    service: String,
    referenceTime: Date,
    lookbackSeconds: TimeInterval
) -> [ProcessCandidate] {
    var query = LogQuery.tccDefault
    query.since = referenceTime.addingTimeInterval(-lookbackSeconds)
    query.until = referenceTime.addingTimeInterval(1.0)  // small forward window for clock skew

    guard let events = try? OWLog.tccEvents(query) else { return [] }

    var seenIdentifiers: Set<String> = []
    var candidates: [ProcessCandidate] = []
    for event in events where event.service.rawValue == service {
        guard let accessing = event.accessingProcess else { continue }
        guard !seenIdentifiers.contains(accessing.identifier) else { continue }
        seenIdentifiers.insert(accessing.identifier)

        let secondsBefore = referenceTime.timeIntervalSince(event.timestamp)
        let confidence: AttributionConfidence
        if event.outcome == .allowed && abs(secondsBefore) < 1.0 {
            confidence = .high
        } else if event.outcome == .allowed {
            confidence = .medium
        } else {
            confidence = .medium
        }
        let evidence = "TCC \(event.outcome.displayName) for "
            + "\(service) \(String(format: "%.2f", secondsBefore))s before event"
        candidates.append(ProcessCandidate(
            identifier: accessing.identifier,
            pid: accessing.pid,
            source: .tccRecentRequest,
            confidence: confidence,
            evidence: evidence
        ))
    }
    return candidates
}

// MARK: - Foreground-application attribution

/// Returns a candidate for the foreground application unless it's
/// already represented in the TCC candidates list (don't double-count
/// the same process). NSWorkspace works only on macOS — this whole
/// module is macOS-only via the CMIO / CoreAudio imports.
private func candidateFromForegroundApplication(
    tccCandidates: [ProcessCandidate]
) -> ProcessCandidate? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    let identifier = app.bundleIdentifier ?? app.localizedName ?? "(unknown foreground app)"

    // Skip if TCC already named this process.
    if tccCandidates.contains(where: { $0.identifier == identifier }) {
        return nil
    }
    return ProcessCandidate(
        identifier: identifier,
        pid: app.processIdentifier,
        source: .foregroundApplication,
        confidence: .low,
        evidence: "Frontmost application at event time"
    )
}

private func confidenceRank(_ confidence: AttributionConfidence) -> Int {
    switch confidence {
    case .high: return 0
    case .medium: return 1
    case .low: return 2
    }
}
