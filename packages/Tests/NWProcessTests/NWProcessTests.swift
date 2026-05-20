import Darwin
@testable import NWProcess
import XCTest

final class NWProcessTests: XCTestCase {
    func testAllReturnsAtLeastOneProcess() throws {
        let processes = try NWProcess.all()
        XCTAssertGreaterThan(processes.count, 0, "Expected at least the test runner itself in the process table")
    }

    func testAllContainsCurrentProcess() throws {
        let processes = try NWProcess.all()
        let me = getpid()
        XCTAssertTrue(
            processes.contains(where: { $0.pid == me }),
            "Expected the test process (pid=\(me)) to appear in NWProcess.all()"
        )
    }

    func testSnapshotForCurrentProcessReportsCorrectIdentity() throws {
        let me = getpid()
        let snapshot = try NWProcess.snapshot(pid: me)

        XCTAssertEqual(snapshot.pid, me)
        XCTAssertEqual(snapshot.parentPid, getppid())
        XCTAssertEqual(snapshot.userId, getuid())
        XCTAssertFalse(snapshot.name.isEmpty, "Expected a non-empty process name for self")
    }

    func testSnapshotForCurrentProcessIncludesExecutablePath() throws {
        let snapshot = try NWProcess.snapshot(pid: getpid())
        XCTAssertNotNil(snapshot.path, "Expected proc_pidpath to return a path for the current process")
    }

    func testSnapshotForNonexistentPidThrowsMetadataUnavailable() {
        // PID 0 is reserved (scheduler / swapper); proc_pidinfo refuses it.
        // Using PID 0 as a stable "unreachable" sentinel for this assertion.
        XCTAssertThrowsError(try NWProcess.snapshot(pid: 0)) { error in
            guard case NWProcessError.metadataUnavailable(let pid) = error else {
                return XCTFail("Expected NWProcessError.metadataUnavailable, got \(error)")
            }
            XCTAssertEqual(pid, 0)
        }
    }

    func testParentChainReachesLaunchd() throws {
        // launchd is pid 1; every running process eventually descends from it.
        let processes = try NWProcess.all()
        let byPid = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })

        var current = try NWProcess.snapshot(pid: getpid())
        var hops = 0
        let hopLimit = 64

        while current.pid != 1 && hops < hopLimit {
            guard let parent = byPid[current.parentPid] else {
                // Parent isn't in our snapshot (e.g., reparented to launchd mid-walk
                // or filtered by visibility). Allow this only if we've already
                // climbed past the most likely candidates.
                XCTAssertGreaterThan(hops, 0, "Failed to find any parent for our own process")
                return
            }
            current = parent
            hops += 1
        }

        XCTAssertEqual(current.pid, 1, "Parent chain did not reach launchd within \(hopLimit) hops")
    }
}
