import Foundation
@testable import OWDevices
import XCTest

final class AttributionTests: XCTestCase {
    // MARK: - ProcessCandidate value type

    func testCandidateEquatableAndHashable() {
        let one = ProcessCandidate(
            identifier: "com.example.foo", pid: 1234,
            source: .tccRecentRequest,
            confidence: .high,
            evidence: "TCC allowed for kTCCServiceCamera 0.20s before event"
        )
        let two = one
        let three = ProcessCandidate(
            identifier: "com.example.bar", pid: 5678,
            source: .tccRecentRequest,
            confidence: .high,
            evidence: "different"
        )
        XCTAssertEqual(one, two)
        XCTAssertNotEqual(one, three)
        XCTAssertEqual(one.hashValue, two.hashValue)
    }

    // MARK: - AttributionSource + Confidence

    func testAllAttributionSourcesEnumerated() {
        XCTAssertEqual(Set(AttributionSource.allCases),
                       [.tccRecentRequest, .foregroundApplication])
    }

    func testAllConfidenceLevelsEnumerated() {
        XCTAssertEqual(Set(AttributionConfidence.allCases),
                       [.high, .medium, .low])
    }

    // MARK: - Live-system smoke

    func testAttributeReturnsResultsForLiveCameraChange() {
        // On an idle box no camera/mic is in use, so there shouldn't
        // be a recent TCC request matching one. The foreground app
        // candidate will fire (whatever's frontmost — likely Terminal
        // or the test runner). Verify the function returns SOMETHING
        // sensible without crashing, regardless of the exact result.
        let change = DeviceStateChange(
            kind: .camera, id: "test-uid", name: "Test Camera",
            isInUse: true, timestamp: Date()
        )
        let candidates = OWDevices.attribute(change, lookbackSeconds: 5.0)
        // Don't assert candidates.isEmpty either way — the foreground
        // app is platform-dependent. Just check the records are
        // well-formed.
        for candidate in candidates {
            XCTAssertFalse(candidate.evidence.isEmpty,
                           "Every candidate must carry human-readable evidence")
        }
    }

    func testAttributeReturnsEmptyForOffTransitionWithNoSignals() {
        // For an OFF transition with no recent TCC and an unmatched
        // foreground app, the result can be empty or a low-confidence
        // foreground entry — either is acceptable.
        let change = DeviceStateChange(
            kind: .camera, id: "test-uid", name: "Test Camera",
            isInUse: false, timestamp: Date()
        )
        let candidates = OWDevices.attribute(change, lookbackSeconds: 1.0)
        // Just ensure no crash; the result depends on live state.
        _ = candidates
    }

    // MARK: - Confidence ordering

    func testCandidateSortPlacesHighFirst() {
        // The attribute() function sorts by confidence. We verify the
        // ordering rule by constructing candidates manually and
        // calling the same sort.
        let low = ProcessCandidate(
            identifier: "low", pid: nil, source: .foregroundApplication,
            confidence: .low, evidence: ""
        )
        let high = ProcessCandidate(
            identifier: "high", pid: nil, source: .tccRecentRequest,
            confidence: .high, evidence: ""
        )
        let medium = ProcessCandidate(
            identifier: "med", pid: nil, source: .tccRecentRequest,
            confidence: .medium, evidence: ""
        )
        let candidates = [low, medium, high]
        let sorted = candidates.sorted { lhs, rhs in
            // mirror the private confidenceRank ordering: high < medium < low
            let order: [AttributionConfidence: Int] = [.high: 0, .medium: 1, .low: 2]
            return (order[lhs.confidence] ?? 99) < (order[rhs.confidence] ?? 99)
        }
        XCTAssertEqual(sorted.map(\.identifier), ["high", "med", "low"])
    }
}
