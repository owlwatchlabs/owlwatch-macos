import Foundation
import os

/// Extension-side NSXPCListener wrapper. Owns the listener, the
/// currently-connected app's connection, and a small in-memory
/// queue of unsent events for the brief windows when the app is
/// quitting / restarting.
///
/// Concurrency: methods are safe to call from any queue. Internal
/// state is guarded by a serial dispatch queue rather than an
/// actor because NSXPCListener's delegate calls are synchronous
/// and need synchronous answers.
public final class FlowEventListener: NSObject, @unchecked Sendable {
    /// Mach service name to advertise on. Public so tests can
    /// inject a private name and avoid colliding with a real
    /// running extension.
    public let machServiceName: String

    /// Optional code-signing requirement. `nil` skips the peer
    /// verification — useful when tests run against an unsigned
    /// xctest binary, but production callers should pass
    /// `FlowXPC.codeSigningRequirement` so a malicious or
    /// tampered client gets rejected before any event leaves the
    /// extension.
    public let codeSigningRequirement: String?

    /// Soft upper bound on the held-back queue. If the app stays
    /// disconnected, the extension drops oldest-first beyond this
    /// — the sysext sandbox is memory-constrained and dropping is
    /// the right trade-off vs. unbounded growth.
    public let bufferLimit: Int

    // Adapter (defined below) needs to read these — keep them
    // fileprivate so the adapter has access without widening the
    // public surface.
    fileprivate let log = Logger(
        subsystem: "com.owlwatchlabs.owlwatch.contentfilter",
        category: "flow-listener"
    )
    private let queue = DispatchQueue(label: "owlwatch.flow-listener")
    private let encoder = FlowXPC.makeEncoder()
    private lazy var listener: NSXPCListener = {
        let listener = NSXPCListener(machServiceName: machServiceName)
        listener.delegate = self
        return listener
    }()
    fileprivate var currentConnection: NSXPCConnection?
    /// FlowEvents that arrived while the app was disconnected.
    /// Drained in FIFO order the moment the app's `register` reply
    /// completes.
    private var buffer: [FlowEvent] = []

    public init(
        machServiceName: String = FlowXPC.machServiceName,
        codeSigningRequirement: String? = FlowXPC.codeSigningRequirement,
        bufferLimit: Int = 4096
    ) {
        self.machServiceName = machServiceName
        self.codeSigningRequirement = codeSigningRequirement
        self.bufferLimit = bufferLimit
    }

    /// Start the listener. Safe to call multiple times; the
    /// underlying NSXPCListener is started once.
    public func resume() {
        listener.resume()
        log.info("listener resumed on \(self.machServiceName, privacy: .public)")
    }

    /// Push an event to the app. If the app isn't connected the
    /// event lands in the bounded buffer and gets delivered the
    /// next time the app calls `register`.
    public func deliver(_ event: FlowEvent) {
        queue.async { [weak self] in
            guard let self else { return }
            if let connection = currentConnection,
               let appProxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] error in
                   self?.log.error("XPC proxy error: \(error.localizedDescription, privacy: .public)")
               }) as? FlowAppXPC {
                if let data = try? encoder.encode(event) {
                    appProxy.deliver(data)
                }
            } else {
                // App not connected — buffer the event, drop
                // oldest if we hit the cap.
                buffer.append(event)
                if buffer.count > bufferLimit {
                    buffer.removeFirst(buffer.count - bufferLimit)
                }
            }
        }
    }

    /// Drain whatever's in the buffer onto the connected app.
    /// Called on a successful `register` handshake.
    fileprivate func drain(into appProxy: FlowAppXPC) {
        let drained = buffer
        buffer.removeAll(keepingCapacity: true)
        for event in drained {
            if let data = try? encoder.encode(event) {
                appProxy.deliver(data)
            }
        }
    }
}

// MARK: - NSXPCListenerDelegate

extension FlowEventListener: NSXPCListenerDelegate {
    public func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        // Peer verification — reject anything not signed by us
        // before any payload crosses. macOS 13+ enforces this
        // synchronously inside the XPC runtime once set; older
        // systems silently skip (they'd reject the connection at
        // a different layer if the binary wasn't trusted).
        if let requirement = codeSigningRequirement, #available(macOS 13.0, *) {
            newConnection.setCodeSigningRequirement(requirement)
        }

        newConnection.exportedInterface = NSXPCInterface(with: FlowExtensionXPC.self)
        newConnection.exportedObject = ExtensionXPCAdapter(owner: self)
        newConnection.remoteObjectInterface = NSXPCInterface(with: FlowAppXPC.self)

        newConnection.interruptionHandler = { [weak self] in
            self?.handleDisconnect(reason: "interrupted")
        }
        newConnection.invalidationHandler = { [weak self] in
            self?.handleDisconnect(reason: "invalidated")
        }

        // Capture by reference into the serial queue. NSXPCConnection
        // isn't `Sendable`, so we wrap in an unsafe untyped box that
        // the dispatch block uses without crossing isolation
        // boundaries — the connection has its own thread safety
        // (it's Cocoa XPC) so this is sound.
        let boxed = UnsafeConnectionBox(connection: newConnection)
        queue.async { [weak self] in
            self?.currentConnection = boxed.connection
        }
        newConnection.resume()
        log.info("accepted connection from app")
        return true
    }

    private func handleDisconnect(reason: String) {
        queue.async { [weak self] in
            self?.log.info("app connection \(reason, privacy: .public)")
            self?.currentConnection = nil
        }
    }
}

// MARK: - Adapter

/// Object NSXPCConnection vends to the connected app when it
/// invokes the extension's exported interface. Kept private so
/// the public surface is just `FlowEventListener.deliver(_:)`.
private final class ExtensionXPCAdapter: NSObject, FlowExtensionXPC {
    private weak var owner: FlowEventListener?

    init(owner: FlowEventListener) {
        self.owner = owner
    }

    func register(reply: @escaping (Bool) -> Void) {
        guard let owner else { reply(false); return }
        owner.log.info("app registered")
        // Drain whatever queued up while the app was away.
        if let connection = owner.currentConnection,
           let appProxy = connection.remoteObjectProxyWithErrorHandler({ _ in })
            as? FlowAppXPC {
            owner.drain(into: appProxy)
        }
        reply(true)
    }

    func ping(reply: @escaping () -> Void) {
        reply()
    }
}

/// Sendable shim so dispatch-queue captures of NSXPCConnection
/// (which isn't `Sendable`) don't trip Swift 6's strict
/// concurrency checks. NSXPCConnection is documented as
/// thread-safe; this box just papers over the missing protocol
/// conformance.
private struct UnsafeConnectionBox: @unchecked Sendable {
    let connection: NSXPCConnection
}
