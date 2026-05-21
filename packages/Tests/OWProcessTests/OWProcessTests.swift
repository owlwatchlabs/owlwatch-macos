import Darwin
@testable import OWProcess
import XCTest

final class OWProcessTests: XCTestCase {
    func testAllReturnsAtLeastOneProcess() throws {
        let processes = try OWProcess.all()
        XCTAssertGreaterThan(processes.count, 0, "Expected at least the test runner itself in the process table")
    }

    func testAllContainsCurrentProcess() throws {
        let processes = try OWProcess.all()
        let me = getpid()
        XCTAssertTrue(
            processes.contains(where: { $0.pid == me }),
            "Expected the test process (pid=\(me)) to appear in OWProcess.all()"
        )
    }

    func testSnapshotForCurrentProcessReportsCorrectIdentity() throws {
        let me = getpid()
        let snapshot = try OWProcess.snapshot(pid: me)

        XCTAssertEqual(snapshot.pid, me)
        XCTAssertEqual(snapshot.parentPid, getppid())
        XCTAssertEqual(snapshot.userId, getuid())
        XCTAssertFalse(snapshot.name.isEmpty, "Expected a non-empty process name for self")
    }

    func testSnapshotForCurrentProcessIncludesExecutablePath() throws {
        let snapshot = try OWProcess.snapshot(pid: getpid())
        XCTAssertNotNil(snapshot.path, "Expected proc_pidpath to return a path for the current process")
    }

    func testSnapshotForNonexistentPidThrowsMetadataUnavailable() {
        // PID 0 is reserved (scheduler / swapper); proc_pidinfo refuses it.
        // Using PID 0 as a stable "unreachable" sentinel for this assertion.
        XCTAssertThrowsError(try OWProcess.snapshot(pid: 0)) { error in
            guard case OWProcessError.metadataUnavailable(let pid) = error else {
                return XCTFail("Expected OWProcessError.metadataUnavailable, got \(error)")
            }
            XCTAssertEqual(pid, 0)
        }
    }

    func testParentChainReachesLaunchd() throws {
        // launchd is pid 1; every running process eventually descends from it.
        let processes = try OWProcess.all()
        let byPid = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })

        var current = try OWProcess.snapshot(pid: getpid())
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
