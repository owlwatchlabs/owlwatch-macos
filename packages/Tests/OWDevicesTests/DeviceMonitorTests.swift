import CoreMediaIO
import Foundation
@testable import OWDevices
import XCTest

final class DeviceMonitorTests: XCTestCase {
    // MARK: - DeviceStateChange value type

    func testStateChangeEquatableAndHashable() {
        let timestamp = Date(timeIntervalSince1970: 0)
        let one = DeviceStateChange(
            kind: .camera, id: "uid", name: "Cam",
            isInUse: true, timestamp: timestamp
        )
        let two = DeviceStateChange(
            kind: .camera, id: "uid", name: "Cam",
            isInUse: true, timestamp: timestamp
        )
        let three = DeviceStateChange(
            kind: .camera, id: "uid", name: "Cam",
            isInUse: false, timestamp: timestamp
        )
        XCTAssertEqual(one, two)
        XCTAssertNotEqual(one, three)
        XCTAssertEqual(one.hashValue, two.hashValue)
    }

    func testStateChangeCarriesAllFields() {
        let when = Date()
        let change = DeviceStateChange(
            kind: .microphone, id: "mic-1", name: "Built-in",
            isInUse: false, timestamp: when
        )
        XCTAssertEqual(change.kind, .microphone)
        XCTAssertEqual(change.id, "mic-1")
        XCTAssertEqual(change.name, "Built-in")
        XCTAssertEqual(change.isInUse, false)
        XCTAssertEqual(change.timestamp, when)
    }

    // MARK: - CMIO device map (used by listener registration)

    func testEnumerateCMIODevicesByUIDReturnsKnownDevices() {
        let map = enumerateCMIODevicesByUID()
        // Every CMIO device should map a non-empty UID to a non-zero ID.
        for (uid, device) in map {
            XCTAssertFalse(uid.isEmpty)
            XCTAssertGreaterThan(device, 0)
        }
        // The map should agree with the M11.1 in-use map on the set
        // of UIDs — same enumeration source, just different return shape.
        let stateMap = enumerateCMIOInUseStateByUID()
        XCTAssertEqual(Set(map.keys), Set(stateMap.keys),
                       "Both CMIO enumerators should see the same device UIDs")
    }

    // MARK: - HAL property readers

    func testCMIOIsRunningProbeDoesNotCrash() {
        let map = enumerateCMIODevicesByUID()
        for (_, device) in map {
            // Just calling readCMIODeviceIsRunningById should not
            // crash regardless of the device's actual state.
            _ = readCMIODeviceIsRunningById(device)
        }
    }

    func testCoreAudioIsRunningProbeDoesNotCrash() {
        let mics = enumerateCoreAudioMicrophones()
        for mic in mics {
            _ = readCoreAudioDeviceIsRunning(mic.id)
        }
    }

    // MARK: - Monitor lifecycle smoke

    func testMonitorStreamCanBeCreatedAndCancelled() async throws {
        // Cancelling the AsyncStream should tear down listeners
        // without crashing. We don't assert any specific event is
        // received — would need to open a real camera/mic in the
        // test process, which conflicts with TCC and the test
        // runner's audio surface. Just verify lifecycle.
        let task = Task {
            for try await _ in OWDevices.monitor() {
                // ignore; just consume until cancelled
            }
        }
        try await Task.sleep(nanoseconds: 200_000_000)  // 200ms
        task.cancel()
        // Give the cancellation handler a moment to deregister listeners.
        try await Task.sleep(nanoseconds: 200_000_000)
        // No assertion needed — we passed if we got here without crashing.
    }
}
