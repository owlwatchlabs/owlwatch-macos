import OWNetwork

/// Well-known port → likely service name. Returns `nil` for
/// anything not in the curated table — **no guessing on
/// ephemeral or non-standard ports**.
///
/// This is an inference, not an assertion: the UI must render the
/// result with a trailing `?` and a "guessed from port — traffic
/// not inspected" caveat. We are not inspecting traffic and never
/// will from this code path (that's M7 territory, entitlement-gated).
///
/// The table is intentionally short. Adding a port here is a UX
/// decision: every entry expands the surface where the UI makes a
/// claim it can't fully back up. Keep it to ports the audience
/// recognizes at a glance (browsers/SSH/SMTP/IMAP/POP/DNS).
public func serviceGuess(port: UInt16?, proto: TransportProtocol) -> String? {
    guard let port else { return nil }
    switch (port, proto) {
    case (443, _):           return "https"
    case (80, _):             return "http"
    case (53, _):             return "dns"
    case (22, _):             return "ssh"
    case (21, _):             return "ftp"
    case (25, _), (587, _):  return "smtp"
    case (993, _):           return "imaps"
    case (995, _):           return "pop3s"
    default:                  return nil
    }
}
