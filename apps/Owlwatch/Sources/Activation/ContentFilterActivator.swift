import Foundation
import NetworkExtension
import os
import SystemExtensions

/// Manages the M7 Content Filter system extension's installation
/// and the matching NEFilterManager configuration.
///
/// Lifecycle:
/// 1. Caller hits `requestActivation()`.
/// 2. We file an `OSSystemExtensionRequest` for the content-filter
///    bundle. The system prompts the user (the
///    `NSSystemExtensionUsageDescription` from the app's Info.plist
///    appears in that sheet).
/// 3. On `.completed` / `.willCompleteAfterReboot`, we configure
///    `NEFilterManager` so the sysext is wired up as the filter
///    data provider and `filterSockets = true`. macOS then surfaces
///    a second approval (the "Allow Owlwatch to filter network
///    content" prompt) before turning the filter on.
///
/// M7.1 scope: this class only handles activation + configuration.
/// FlowEvent delivery / XPC plumbing lands in M7.2.
///
/// Posture:
/// - `@MainActor` because the SwiftUI views observe `state`
///   directly. The OSSystemExtensionRequest delegate callbacks
///   arrive on the queue we hand the request (we pass `.main`).
/// - `@Observable` so SwiftUI views re-render when state changes
///   without an explicit `ObservableObject` wrapper.
@MainActor
@Observable
final class ContentFilterActivator: NSObject {
    /// Bundle identifier of the OwlwatchContentFilter system
    /// extension. Must match `PRODUCT_BUNDLE_IDENTIFIER` for the
    /// target in `project.yml` and the bundle's `CFBundleIdentifier`.
    static let extensionBundleID = "com.owlwatchlabs.owlwatch.contentfilter"

    enum State: Equatable {
        case idle
        case requestingActivation
        case awaitingUserApproval
        case configuringFilter
        case enabled
        case willCompleteAfterReboot
        case failed(String)
    }

    private(set) var state: State = .idle

    private let log = Logger(
        subsystem: "com.owlwatchlabs.owlwatch",
        category: "content-filter-activator"
    )

    // MARK: - Public surface

    /// Submit the activation request to the system. Safe to call
    /// repeatedly — macOS treats subsequent requests as upgrade /
    /// replacement passes.
    func requestActivation() {
        log.info("requesting activation for \(Self.extensionBundleID, privacy: .public)")
        state = .requestingActivation
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: Self.extensionBundleID,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    /// Refresh from `NEFilterManager` on app launch so the state
    /// chip reflects the current OS-level reality (the user may
    /// have installed previously, rebooted, then come back to a
    /// fresh app launch).
    func reconcileFromPreferences() async {
        do {
            try await NEFilterManager.shared().loadFromPreferences()
            if NEFilterManager.shared().isEnabled {
                state = .enabled
            }
        } catch {
            log.error("loadFromPreferences failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Filter manager wiring

    /// Configure `NEFilterManager.shared()` to use our system
    /// extension as its filter data provider, then enable + save.
    /// Called from `request(_:didFinishWithResult:)` once activation
    /// succeeds.
    fileprivate func configureFilterManager() async {
        state = .configuringFilter
        let manager = NEFilterManager.shared()
        do {
            try await manager.loadFromPreferences()
        } catch {
            log.error("loadFromPreferences before save failed: \(error.localizedDescription, privacy: .public)")
            // Continue anyway — saveToPreferences will surface a
            // clearer error if the load was actually unrecoverable.
        }
        // Per Apple's 2026 NetworkExtension docs: bundle-ID wiring
        // for a sysext content filter is via the runtime config's
        // `filterDataProviderBundleIdentifier` — there is no
        // Info.plist equivalent.
        let configuration = NEFilterProviderConfiguration()
        configuration.filterSockets = true
        // `filterBrowsers` is deprecated on macOS (it never did
        // anything outside iOS). `filterPackets` is for packet-
        // tunnel providers, not what we want.
        configuration.filterPackets = false
        configuration.filterDataProviderBundleIdentifier = Self.extensionBundleID
        configuration.organization = "Owlwatch"
        manager.providerConfiguration = configuration
        manager.localizedDescription = "Owlwatch Content Filter"
        manager.isEnabled = true
        do {
            try await manager.saveToPreferences()
            log.info("NEFilterManager saved, filter enabled")
            state = .enabled
        } catch {
            log.error("saveToPreferences failed: \(error.localizedDescription, privacy: .public)")
            state = .failed("Couldn't enable the filter: \(error.localizedDescription)")
        }
    }
}

// MARK: - OSSystemExtensionRequestDelegate

extension ContentFilterActivator: OSSystemExtensionRequestDelegate {
    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension extension: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        // Always swap to the version this app brought. Apple's
        // sample code does the same — anything else risks running
        // an old extension against a new app build.
        return .replace
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Task { @MainActor in
            self.log.info("user approval required")
            self.state = .awaitingUserApproval
        }
    }

    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        didFinishWithResult result: OSSystemExtensionRequest.Result
    ) {
        Task { @MainActor in
            self.log.info("request finished — result=\(result.rawValue, privacy: .public)")
            switch result {
            case .completed:
                await self.configureFilterManager()
            case .willCompleteAfterReboot:
                self.state = .willCompleteAfterReboot
            @unknown default:
                self.state = .failed("Unknown activation result.")
            }
        }
    }

    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            self.log.error("activation failed: \(error.localizedDescription, privacy: .public)")
            self.state = .failed(error.localizedDescription)
        }
    }
}
