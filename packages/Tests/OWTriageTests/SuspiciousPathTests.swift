import Foundation
@testable import OWTriage
import XCTest

final class SuspiciousPathTests: XCTestCase {
    func testNilIsNotSuspicious() {
        XCTAssertFalse(isSuspiciousPath(nil))
    }

    func testTmpPrefixes() {
        XCTAssertTrue(isSuspiciousPath("/tmp/payload"))
        XCTAssertTrue(isSuspiciousPath("/private/tmp/payload"))
        XCTAssertTrue(isSuspiciousPath("/var/tmp/payload"))
        XCTAssertTrue(isSuspiciousPath("/private/var/tmp/payload"))
    }

    func testHiddenDirInPath() {
        // Anywhere in the path matters — dropper stashes its
        // payload in a dot-dir to escape casual file-browser
        // inspection.
        XCTAssertTrue(isSuspiciousPath("/Users/anon/.cache/loader"))
        XCTAssertTrue(isSuspiciousPath("/var/folders/abc/T/.hidden/foo"))
    }

    func testUserLibraryIsSuspicious() {
        // Owlwatch flags execution origins under ~/Library/ — less
        // common than /Applications/ for legit installs, common
        // for malware persistence.
        let home = NSHomeDirectory()
        XCTAssertTrue(isSuspiciousPath("\(home)/Library/Application Support/badthing/run"))
    }

    func testUserLocalIsSuspicious() {
        let home = NSHomeDirectory()
        XCTAssertTrue(isSuspiciousPath("\(home)/.local/bin/helperd"))
    }

    func testBenignSystemPathsAreNotSuspicious() {
        XCTAssertFalse(isSuspiciousPath("/bin/ls"))
        XCTAssertFalse(isSuspiciousPath("/usr/bin/grep"))
        XCTAssertFalse(isSuspiciousPath("/usr/libexec/kextd"))
        XCTAssertFalse(isSuspiciousPath("/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"))
    }

    func testApplicationsIsNotSuspicious() {
        XCTAssertFalse(isSuspiciousPath("/Applications/Safari.app/Contents/MacOS/Safari"))
    }
}
