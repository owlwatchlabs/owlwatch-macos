import NetworkExtension
import os

/// M7.1 Content Filter system extension — scaffold.
///
/// This subclass owns the NEFilterDataProvider lifecycle: the system
/// instantiates it inside the sandboxed sysext process after the
/// container app activates and enables the filter. M7.1 covers
/// scaffolding only — the provider stands up, accepts the start /
/// stop lifecycle, and pass-through-allows every flow. M7.2 will
/// add the FlowEvent emission + XPC channel; M7.3 wires the UI.
///
/// Posture:
/// - Visibility milestone, not enforcement. Every flow returns
///   `.allow()`. The verdict structure is preserved so a future
///   policy decision can be slotted in without re-architecting.
/// - The provider has no disk / network access (sysext sandbox).
///   Anything that needs to leave the sysext goes over XPC to the
///   container app — landing in M7.2.
final class ContentFilterProvider: NEFilterDataProvider {
    private let log = Logger(
        subsystem: "com.owlwatchlabs.owlwatch.contentfilter",
        category: "provider"
    )

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        log.info("startFilter — M7.1 visibility-only scaffold")
        // No upstream state to load yet. M7.2 will dial the XPC
        // channel here so the container app starts receiving events
        // as soon as the system asks us to filter.
        completionHandler(nil)
    }

    override func stopFilter(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        log.info("stopFilter — reason=\(reason.rawValue)")
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        // M7.1: visibility-only pass-through. Returning `.allow()`
        // tells the kernel filter we don't need to see the payload —
        // socket open/close events still surface to handleNewFlow,
        // which is exactly what M7.2's FlowEvent capture wants.
        return .allow()
    }
}
