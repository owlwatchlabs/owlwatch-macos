import Foundation

/// M7.2 — the XPC contract between the M7 Content Filter system
/// extension and the Owlwatch container app.
///
/// Direction:
/// - **Extension → app**: `FlowAppXPC.deliver(_:)` pushes JSON-
///   encoded `FlowEvent`s as they arrive at `handleNewFlow`.
///   Fire-and-forget; the extension can't tell the app what to do
///   about them.
/// - **App → extension**: `FlowExtensionXPC.register(reply:)` is
///   the handshake; `.ping(reply:)` keeps the link warm.
///
/// The extension is the **listener** (it outlives the app) and the
/// app is the client that dials in when it launches. This mirrors
/// Apple's "Filtering Network Traffic" IPCConnection sample.

// MARK: - Protocols

/// Methods the **extension** exposes for the **app** to call.
/// `@objc` because NSXPCConnection requires Objective-C-shaped
/// protocols. The Sendable warning is suppressed because Cocoa
/// XPC promises thread safety on its proxies — not Swift Sendable.
@objc public protocol FlowExtensionXPC {
    /// Handshake — must be the first call after connecting. Reply
    /// is the extension's view of whether it's ready to stream.
    /// `false` is a permanent refusal (e.g. filter not configured);
    /// `true` means the extension will start invoking `deliver(_:)`
    /// on the app's exported object as flows arrive.
    func register(reply: @escaping (Bool) -> Void)

    /// Heartbeat — keeps the connection in the "established" pool
    /// so XPC doesn't tear it down for idleness. The reply has no
    /// payload because we only care that the round trip completes.
    func ping(reply: @escaping () -> Void)
}

/// Methods the **app** exposes for the **extension** to call.
/// The payload is a JSON-encoded `FlowEvent` (encoded with the
/// `JSONEncoder` defaults) so the wire format stays a single Data
/// blob — easier to evolve than reshaping `@objc`-visible structs.
@objc public protocol FlowAppXPC {
    /// Deliver one flow event. Fire-and-forget; the extension does
    /// not block on the reply.
    func deliver(_ encodedFlowEvent: Data)
}

// MARK: - Constants

public enum FlowXPC {
    /// Mach service name. Apple's documented pattern for sysext →
    /// app communication is to prefix the App Group identifier so
    /// launchd can resolve the name across the sysext sandbox. The
    /// App Group `group.com.owlwatchlabs.owlwatch` is configured on
    /// both targets' entitlements (M7.1).
    public static let machServiceName = "group.com.owlwatchlabs.owlwatch.flow"

    /// Code-signing requirement applied via NSXPCConnection's
    /// `setCodeSigningRequirement(_:)` on macOS 13+. Restricts the
    /// peer to a binary signed by OwlWatch Labs (Team ID
    /// `8VA5VUL6X6`) under an Apple-rooted certificate. Both sides
    /// set this so each independently rejects an impostor peer.
    public static let codeSigningRequirement =
        "anchor apple generic and certificate leaf[subject.OU] = \"8VA5VUL6X6\""

    /// JSON encoder / decoder used on the wire. Re-exported so
    /// both sides agree on the date strategy without each
    /// instantiating their own.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
