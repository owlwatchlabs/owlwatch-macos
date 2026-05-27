import Foundation
import os

/// App-side counterpart of `FlowEventListener`. Opens an
/// `NSXPCConnection` to the extension's Mach service, handshakes
/// with `register`, and surfaces incoming `FlowEvent`s via a
/// caller-supplied closure.
///
/// Concurrency: the closure is invoked on `queue` (defaults to
/// the main queue) so the consumer can mutate `@MainActor`
/// observables without an additional hop.
public final class FlowEventClient: NSObject, @unchecked Sendable {
    public let machServiceName: String
    public let codeSigningRequirement: String?

    /// Callback fired for every flow event the extension pushes.
    /// Always called on `callbackQueue` — defaults to `.main`.
    public let onEvent: @Sendable (FlowEvent) -> Void

    /// Fired when the connection's state changes meaningfully
    /// (handshake complete, dropped, failed). Optional — provide
    /// it if the UI needs to render a connectivity indicator.
    public let onState: (@Sendable (State) -> Void)?

    public let callbackQueue: DispatchQueue

    public enum State: Sendable, Equatable {
        case idle
        case connecting
        case connected
        case disconnected(reason: String)
    }

    private let log = Logger(
        subsystem: "com.owlwatchlabs.owlwatch",
        category: "flow-client"
    )
    private let decoder = FlowXPC.makeDecoder()
    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private var state: State = .idle

    public init(
        machServiceName: String = FlowXPC.machServiceName,
        codeSigningRequirement: String? = FlowXPC.codeSigningRequirement,
        callbackQueue: DispatchQueue = .main,
        onState: (@Sendable (State) -> Void)? = nil,
        onEvent: @escaping @Sendable (FlowEvent) -> Void
    ) {
        self.machServiceName = machServiceName
        self.codeSigningRequirement = codeSigningRequirement
        self.callbackQueue = callbackQueue
        self.onState = onState
        self.onEvent = onEvent
    }

    /// Open the connection and run the handshake. Safe to call
    /// repeatedly — a second call reuses the existing connection
    /// when it's still alive.
    public func connect() {
        lock.lock()
        if connection != nil { lock.unlock(); return }
        let conn = NSXPCConnection(
            machServiceName: machServiceName,
            options: .privileged
        )

        if let requirement = codeSigningRequirement, #available(macOS 13.0, *) {
            conn.setCodeSigningRequirement(requirement)
        }

        conn.remoteObjectInterface = NSXPCInterface(with: FlowExtensionXPC.self)
        conn.exportedInterface = NSXPCInterface(with: FlowAppXPC.self)
        conn.exportedObject = ClientXPCAdapter(owner: self)

        conn.interruptionHandler = { [weak self] in
            self?.transition(.disconnected(reason: "interrupted"))
        }
        conn.invalidationHandler = { [weak self] in
            self?.transition(.disconnected(reason: "invalidated"))
        }

        connection = conn
        lock.unlock()

        transition(.connecting)
        conn.resume()

        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ [weak self] error in
            self?.log.error("proxy error: \(error.localizedDescription, privacy: .public)")
            self?.transition(.disconnected(reason: error.localizedDescription))
        }) as? FlowExtensionXPC else {
            transition(.disconnected(reason: "proxy cast failed"))
            return
        }

        proxy.register { [weak self] success in
            guard let self else { return }
            self.transition(success ? .connected : .disconnected(reason: "register refused"))
        }
    }

    /// Tear down the connection. Subsequent `connect()` calls will
    /// open a fresh one.
    public func disconnect() {
        lock.lock()
        let conn = connection
        connection = nil
        lock.unlock()
        conn?.invalidate()
        transition(.disconnected(reason: "client closed"))
    }

    // MARK: - Internals

    fileprivate func handleEvent(_ data: Data) {
        guard let event = try? decoder.decode(FlowEvent.self, from: data) else {
            log.error("failed to decode FlowEvent payload (\(data.count, privacy: .public) bytes)")
            return
        }
        callbackQueue.async { [onEvent] in
            onEvent(event)
        }
    }

    private func transition(_ next: State) {
        lock.lock()
        let previous = state
        state = next
        lock.unlock()
        if previous != next, let onState {
            callbackQueue.async { onState(next) }
        }
    }
}

// MARK: - Adapter

/// Vended to the extension as the app's exported object — the
/// extension calls `deliver(_:)` on this for every FlowEvent.
private final class ClientXPCAdapter: NSObject, FlowAppXPC {
    private weak var owner: FlowEventClient?

    init(owner: FlowEventClient) {
        self.owner = owner
    }

    func deliver(_ encodedFlowEvent: Data) {
        owner?.handleEvent(encodedFlowEvent)
    }
}
