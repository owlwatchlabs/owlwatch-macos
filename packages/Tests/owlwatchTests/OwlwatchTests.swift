import OWProcess
@testable import owlwatch
import XCTest

final class OwlwatchTests: XCTestCase {
    private let three = RunningProcess(pid: 3, parentPid: 1, name: "child-of-1", path: nil, userId: 0)
    private let four = RunningProcess(pid: 4, parentPid: 1, name: "sibling-of-3", path: nil, userId: 0)
    private let five = RunningProcess(pid: 5, parentPid: 3, name: "grandchild-3-5", path: nil, userId: 0)
    private let six = RunningProcess(pid: 6, parentPid: 5, name: "great-grandchild-3-5-6", path: nil, userId: 0)
    private let seven = RunningProcess(pid: 7, parentPid: 99, name: "orphan", path: nil, userId: 0)

    private var snapshot: [RunningProcess] {
        [three, four, five, six, seven]
    }

    func testFocusWithoutPidReturnsSnapshotUnchanged() {
        let result = focus(snapshot, pid: nil, tree: false)
        XCTAssertEqual(result.map(\.pid), snapshot.map(\.pid))
    }

    func testFocusInTableModeReturnsOnlyMatchingPid() {
        let result = focus(snapshot, pid: 3, tree: false)
        XCTAssertEqual(result.map(\.pid), [3])
    }

    func testFocusInTableModeReturnsEmptyForMissingPid() {
        let result = focus(snapshot, pid: 999, tree: false)
        XCTAssertEqual(result, [])
    }

    func testFocusInTreeModeIncludesDescendants() {
        let result = focus(snapshot, pid: 3, tree: true)
        // 3 itself + 5 (child) + 6 (grandchild). 4 (sibling) excluded; 7 (orphan) excluded.
        XCTAssertEqual(Set(result.map(\.pid)), Set([3, 5, 6]))
    }

    func testFocusInTreeModeForLeafPidReturnsJustThatPid() {
        let result = focus(snapshot, pid: 6, tree: true)
        XCTAssertEqual(result.map(\.pid), [6])
    }

    func testFocusInTreeModeForMissingPidReturnsEmpty() {
        let result = focus(snapshot, pid: 999, tree: true)
        XCTAssertEqual(result, [])
    }
}
