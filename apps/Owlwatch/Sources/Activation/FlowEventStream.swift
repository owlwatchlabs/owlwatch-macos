import Foundation
import OWNetworkExt
import os
import SwiftUI

/// App-side consumer of the M7.2 flow stream from the
/// OwlwatchContentFilter system extension. Owns the
/// `FlowEventClient` and holds a bounded ring of recent
/// `FlowEvent`s for the UI to observe.
///
/// Scope here is small on purpose — the M7.3 Network surface will
/// read `recentEvents` and render them. Any heavier aggregation
/// (joining flows to processes, deduping by 4-tuple, etc.) lives
/// in the consumer view's view-model, not here.
///
/// Concurrency:
/// - `@MainActor` because SwiftUI reads it directly.
/// - The underlying `FlowEventClient` invokes its callback on the
///   main queue, so the append into `recentEvents` is already on
///   the main actor by the time we touch it.
@MainActor
@Observable
final class FlowEventStream {
    /// Ring buffer of recent events. Newest-last. Bounded so a
    /// chatty system doesn't push UI memory unbounded.
    private(set) var recentEvents: [FlowEvent] = []

    /// XPC connection state surfaced for UI ("connecting…",
    /// "connected", "extension offline" etc.).
    private(set) var connectionState: FlowEventClient.State = .idle

    /// Maximum number of events kept in `recentEvents`. Crossing
    /// this trims oldest-first. 5,000 is generous (~5 minutes of
    /// busy-system traffic) but well under any UI render budget.
    var bufferLimit: Int = 5000

    private let log = Logger(
        subsystem: "com.owlwatchlabs.owlwatch",
        category: "flow-stream"
    )
    private var client: FlowEventClient?

    /// Open the XPC channel to the extension. Idempotent — a
    /// second call while connected is a no-op.
    func start() {
        if client != nil { return }
        let client = FlowEventClient(
            onState: { [weak self] state in
                Task { @MainActor in
                    self?.connectionState = state
                }
            },
            onEvent: { [weak self] event in
                Task { @MainActor in
                    self?.append(event)
                }
            }
        )
        self.client = client
        client.connect()
    }

    /// Tear down the XPC channel. M7.3+ may call this on
    /// `onDisappear` of the Network surface if it wants to stop
    /// draining; for now it stays open across section switches.
    func stop() {
        client?.disconnect()
        client = nil
    }

    /// Drop the in-memory ring without touching the XPC channel.
    func clear() {
        recentEvents.removeAll(keepingCapacity: true)
    }

    private func append(_ event: FlowEvent) {
        recentEvents.append(event)
        if recentEvents.count > bufferLimit {
            recentEvents.removeFirst(recentEvents.count - bufferLimit)
        }
    }
}
