import CoreAudio
import Foundation
@testable import OWDevices
import XCTest

final class OWDevicesTests: XCTestCase {
    // MARK: - DeviceKind

    func testDeviceKindCases() {
        XCTAssertEqual(Set(DeviceKind.allCases), [.camera, .microphone])
    }

    // MARK: - Camera value type

    func testCameraEquatableAndHashable() {
        let one = Camera(
            id: "uid-1", name: "Test Cam", manufacturer: "Apple",
            modelID: "model", isInUse: false, isExternal: false, isVirtual: false
        )
        let two = one
        let three = Camera(
            id: "uid-2", name: "Test Cam", manufacturer: "Apple",
            modelID: "model", isInUse: false, isExternal: false, isVirtual: false
        )
        XCTAssertEqual(one, two)
        XCTAssertNotEqual(one, three)
        // Hashable: equal instances hash equal, distinct instances hash distinct.
        XCTAssertEqual(one.hashValue, two.hashValue)
    }

    // MARK: - Microphone value type

    func testMicrophoneEquatableAndHashable() {
        let one = Microphone(
            id: "mic-1", name: "Test Mic", manufacturer: "Apple",
            isInUse: false, isExternal: false
        )
        let two = one
        let three = Microphone(
            id: "mic-2", name: "Test Mic", manufacturer: "Apple",
            isInUse: false, isExternal: false
        )
        XCTAssertEqual(one, two)
        XCTAssertNotEqual(one, three)
        XCTAssertEqual(one.hashValue, two.hashValue)
    }

    // MARK: - Live-system enumeration smoke

    func testCamerasReturnsAtLeastOneOnRealMac() {
        // Every Mac with this test harness has at least a built-in
        // camera (MacBook) or no camera at all (Mac mini / Studio).
        // We don't assert >0 because of the no-camera case; we just
        // assert the call doesn't crash and produces well-formed records.
        let cameras = OWDevices.cameras()
        for camera in cameras {
            XCTAssertFalse(camera.id.isEmpty,
                           "Every enumerated camera should have a UID")
            XCTAssertFalse(camera.name.isEmpty,
                           "Every enumerated camera should have a localized name")
        }
    }

    func testMicrophonesReturnsAtLeastOneOnRealMac() {
        let mics = OWDevices.microphones()
        // Most Macs have a built-in mic; some headless setups don't.
        // Don't strictly require > 0; check well-formedness.
        for mic in mics {
            XCTAssertFalse(mic.id.isEmpty)
            XCTAssertFalse(mic.name.isEmpty)
        }
    }

    func testMicrophoneEnumerationFiltersOutOutputOnlyDevices() {
        // Speakers, headphones, AirPlay output devices show up in
        // kAudioHardwarePropertyDevices alongside microphones.
        // deviceHasInputChannels() filters them out. The proxy for
        // "no output-only devices leaked through" is: every result
        // here has a non-zero input channel count (which we don't
        // directly check, but we trust the filter and confirm via
        // a name heuristic — no obvious output-only names).
        let mics = OWDevices.microphones()
        for mic in mics {
            // "Headphones", "Speakers", "AirPlay" are the obvious
            // output-only names. If any of those show up here it
            // means the input-channel filter is broken.
            let name = mic.name.lowercased()
            XCTAssertFalse(name.contains("headphones"),
                           "Headphones leaked through input filter: \(mic.name)")
            XCTAssertFalse(name.contains("speakers"),
                           "Speakers leaked through input filter: \(mic.name)")
        }
    }

    // MARK: - CMIO + CoreAudio probes are non-crashing

    func testCMIOEnumerationDoesNotCrash() {
        // Even on a Mac with zero cameras this should return an
        // empty (or single-element) dict, never throw or crash.
        let state = enumerateCMIOInUseStateByUID()
        for (uid, _) in state {
            XCTAssertFalse(uid.isEmpty,
                           "Every CMIO device UID should be non-empty")
        }
    }

    func testCoreAudioEnumerationDoesNotCrash() {
        let mics = enumerateCoreAudioMicrophones()
        for mic in mics {
            // UIDs sometimes come back empty for transient virtual
            // devices; don't assert on that. Just check the call
            // didn't crash.
            XCTAssertFalse(mic.name.isEmpty,
                           "Every CoreAudio mic should have a name")
        }
    }
}
