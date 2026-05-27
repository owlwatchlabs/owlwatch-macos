import NetworkExtension
import OWNetworkExt
import os

/// M7.2 Content Filter system extension — the visibility provider.
///
/// Subclass of `NEFilterDataProvider`. The system instantiates it
/// inside the sandboxed sysext process once the container app
/// activates and enables the filter.
///
/// Behavior:
/// - `startFilter` brings up the `FlowEventListener` that the app
///   dials in over XPC.
/// - `handleNewFlow` shapes each `NEFilterSocketFlow` into a
///   `FlowEvent` (see `FlowExtraction`) and hands it to the
///   listener, which either pushes it to a connected app or
///   buffers it for the next reconnect. Every flow returns
///   `.allow()` — visibility milestone, no enforcement.
///
/// Posture:
/// - The sysext sandbox blocks disk and network. The only outbound
///   path is XPC. The listener accepts a single peer at a time
///   and verifies it against Team ID `8VA5VUL6X6` before
///   delivering anything.
/// - The verdict structure is preserved (`return .allow()`) so a
///   future enforcement decision can drop in here without re-
///   architecting handleNewFlow.
final class ContentFilterProvider: NEFilterDataProvider {
    private let log = Logger(
        subsystem: "com.owlwatchlabs.owlwatch.contentfilter",
        category: "provider"
    )
    private let listener = FlowEventListener()

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        log.info("startFilter — M7.2 flow-event provider")
        listener.resume()
        completionHandler(nil)
    }

    override func stopFilter(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        log.info("stopFilter — reason=\(reason.rawValue, privacy: .public)")
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        if let event = FlowExtraction.event(from: flow) {
            listener.deliver(event)
        }
        // Visibility-only — every flow goes through. The kernel
        // filter won't ask us about subsequent payload bytes
        // because we don't request `.filterDataVerdict(...)`.
        return .allow()
    }
}
