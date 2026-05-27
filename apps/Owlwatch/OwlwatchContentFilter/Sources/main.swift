import Foundation
import NetworkExtension

// System-extension network filter entry point.
//
// Unlike app-extensions (which the host hosts via XPC), a
// NetworkExtension running as a macOS system extension owns its
// own process. `NEProvider.startSystemExtensionMode()` reads the
// principal class from the Info.plist's `NSExtension` dict and
// hands control to the framework's event loop. `dispatchMain()`
// blocks the main thread forever so libdispatch keeps servicing
// the NE callbacks.
//
// Verified against Apple's NetworkExtension sample code (2026):
// this is the canonical entry-point pair for filter-data sysexts.

autoreleasepool {
    NEProvider.startSystemExtensionMode()
}
dispatchMain()
