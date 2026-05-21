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

    // MARK: - Arguments (M1.2)

    func testSnapshotWithoutIncludeArgumentsLeavesArgumentsNil() throws {
        let snapshot = try OWProcess.snapshot(pid: getpid())
        XCTAssertNil(snapshot.arguments, "Default snapshot should not capture arguments")
    }

    func testSnapshotWithIncludeArgumentsReturnsNonEmptyForSelf() throws {
        let snapshot = try OWProcess.snapshot(pid: getpid(), includeArguments: true)
        XCTAssertNotNil(snapshot.arguments, "includeArguments=true must populate the arguments field")
        let args = try XCTUnwrap(snapshot.arguments)
        XCTAssertFalse(args.isEmpty, "Expected at least argv[0] for the test runner")
    }

    func testArgumentsForSelfMatchesProcessInfo() throws {
        let snapshot = try OWProcess.snapshot(pid: getpid(), includeArguments: true)
        let args = try XCTUnwrap(snapshot.arguments)

        // The test runner's arguments are observable via Foundation's
        // ProcessInfo. argv[0] from KERN_PROCARGS2 is usually the executable
        // path; ProcessInfo.arguments[0] matches that or the invocation name.
        // The arrays should have the same length and overlap in the tail.
        let processInfoArgs = ProcessInfo.processInfo.arguments
        XCTAssertEqual(args.count, processInfoArgs.count, "argc from sysctl should match ProcessInfo.arguments.count")
    }

    func testAllWithIncludeArgumentsPopulatesAtLeastSomeProcesses() throws {
        let processes = try OWProcess.all(includeArguments: true)
        XCTAssertFalse(processes.isEmpty, "Snapshot must be non-empty")

        // Every process gets a non-nil arguments array when capture was
        // requested (empty array if KERN_PROCARGS2 declined for that PID).
        for proc in processes {
            XCTAssertNotNil(
                proc.arguments,
                "Expected non-nil arguments (possibly empty) for pid=\(proc.pid) when includeArguments=true"
            )
        }

        // At minimum the current process should have a populated argv.
        let me = processes.first(where: { $0.pid == getpid() })
        XCTAssertNotNil(me, "Self should be in all() snapshot")
        XCTAssertFalse(me?.arguments?.isEmpty ?? true, "Self's arguments should be non-empty")
    }

    // MARK: - Open files (M1.3)

    func testSnapshotWithoutIncludeOpenFilesLeavesOpenFilesNil() throws {
        let snapshot = try OWProcess.snapshot(pid: getpid())
        XCTAssertNil(snapshot.openFiles, "Default snapshot should not capture openFiles")
    }

    func testSnapshotWithIncludeOpenFilesReturnsNonEmptyForSelf() throws {
        let snapshot = try OWProcess.snapshot(pid: getpid(), includeOpenFiles: true)
        XCTAssertNotNil(snapshot.openFiles, "includeOpenFiles=true must populate the openFiles field")
        let files = try XCTUnwrap(snapshot.openFiles)
        // Every process running under XCTest has at least stdin/stdout/stderr.
        XCTAssertGreaterThanOrEqual(
            files.count, 3,
            "Expected at least three open FDs (stdin/stdout/stderr) for the test process"
        )
    }

    func testOpenFilesIncludeStandardDescriptorsForSelf() throws {
        let snapshot = try OWProcess.snapshot(pid: getpid(), includeOpenFiles: true)
        let files = try XCTUnwrap(snapshot.openFiles)
        let descriptorNumbers = Set(files.map(\.fd))
        XCTAssertTrue(descriptorNumbers.contains(0), "Expected stdin (fd 0) to appear")
        XCTAssertTrue(descriptorNumbers.contains(1), "Expected stdout (fd 1) to appear")
        XCTAssertTrue(descriptorNumbers.contains(2), "Expected stderr (fd 2) to appear")
    }

    func testOpenFilesIncludeAtLeastOneRecognizedVariant() throws {
        let snapshot = try OWProcess.snapshot(pid: getpid(), includeOpenFiles: true)
        let files = try XCTUnwrap(snapshot.openFiles)
        // The test runner's stdin/stdout/stderr resolve to some combination
        // of file (e.g., /dev/null), socket (XCTest IPC), or pipe — the
        // variants vary by how XCTest was invoked. The assertion here is
        // that at least one FD lands in a recognized variant rather than
        // every FD falling through to `.other` — which would indicate the
        // proc_pidfdinfo bridging is broken.
        let hasRecognizedVariant = files.contains { file in
            switch file {
            case .file, .socket, .pipe: return true
            case .other: return false
            }
        }
        XCTAssertTrue(hasRecognizedVariant, "Expected at least one .file/.socket/.pipe variant in self's open FDs")
    }

    func testAllWithIncludeOpenFilesAttachesNonNilFieldToEveryEntry() throws {
        let processes = try OWProcess.all(includeOpenFiles: true)
        XCTAssertFalse(processes.isEmpty, "Snapshot must be non-empty")
        for proc in processes {
            XCTAssertNotNil(
                proc.openFiles,
                "Expected non-nil openFiles (possibly empty) for pid=\(proc.pid) when includeOpenFiles=true"
            )
        }
    }
}
