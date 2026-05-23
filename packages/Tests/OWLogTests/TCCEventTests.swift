import Foundation
@testable import OWLog
import XCTest

final class TCCEventTests: XCTestCase {
    // MARK: - Line-shape parsers

    func testExtractMsgIDMatchesTransactionFormat() {
        XCTAssertEqual(
            extractMsgID(from: "REQUEST: tccd_uid=501, msgID=404.34234"),
            "404.34234"
        )
        XCTAssertEqual(
            extractMsgID(from: "AUTHREQ_CTX: msgID=12345.67, service=kTCCServiceCamera"),
            "12345.67"
        )
    }

    func testExtractMsgIDReturnsNilWhenAbsent() {
        XCTAssertNil(extractMsgID(from: "No msgID in this line"))
    }

    func testParseAuthreqCTXExtractsServiceAndPreflight() {
        let message = "AUTHREQ_CTX: msgID=404.1, function=TCCAccessRequest, "
            + "service=kTCCServiceCamera, preflight=yes, query=1"
        let result = parseAuthreqCTX(message)
        XCTAssertEqual(result?.0, .camera)
        XCTAssertEqual(result?.1, true)
    }

    func testParseAuthreqCTXHandlesNonPreflight() {
        let message = "AUTHREQ_CTX: msgID=404.1, service=kTCCServiceMicrophone, preflight=no"
        let result = parseAuthreqCTX(message)
        XCTAssertEqual(result?.0, .microphone)
        XCTAssertEqual(result?.1, false)
    }

    func testParseAuthreqCTXPreservesUnknownService() {
        let message = "AUTHREQ_CTX: msgID=404.1, service=kTCCServiceFutureKind, preflight=yes"
        guard case .other(let raw) = parseAuthreqCTX(message)?.0 else {
            return XCTFail("Unknown TCC services should land in .other(rawValue:)")
        }
        XCTAssertEqual(raw, "kTCCServiceFutureKind")
    }

    func testParseAuthreqAttribution() {
        let message = """
        AUTHREQ_ATTRIBUTION: msgID=404.34234, attribution={accessing={TCCDProcess: \
        identifier=net.whatsapp.WhatsApp, pid=1466, auid=501, euid=501, \
        binary_path=/Applications/WhatsApp.app/Contents/MacOS/WhatsApp}, \
        requesting={TCCDProcess: identifier=com.apple.cmio.ContinuityCaptureAgent, \
        pid=404, auid=501, euid=501, binary_path=/usr/libexec/ContinuityCaptureAgent}, },
        """
        let (accessing, requesting) = parseAuthreqAttribution(message)
        XCTAssertEqual(accessing?.identifier, "net.whatsapp.WhatsApp")
        XCTAssertEqual(accessing?.pid, 1466)
        XCTAssertEqual(accessing?.binaryPath, "/Applications/WhatsApp.app/Contents/MacOS/WhatsApp")
        XCTAssertEqual(requesting?.identifier, "com.apple.cmio.ContinuityCaptureAgent")
        XCTAssertEqual(requesting?.pid, 404)
    }

    func testParseAuthreqResult() {
        let message = "AUTHREQ_RESULT: msgID=404.34234, authValue=0, authReason=10, error=(null)"
        let result = parseAuthreqResult(message)
        XCTAssertEqual(result?.0, 0)
        XCTAssertEqual(result?.1, 10)
    }

    // MARK: - Outcome / Service mapping

    func testOutcomeMappingClassifiesObservedValues() {
        XCTAssertEqual(TCCOutcome.from(authValue: 0), .denied)
        XCTAssertEqual(TCCOutcome.from(authValue: 2), .allowed)
        XCTAssertEqual(TCCOutcome.from(authValue: 3), .allowedLimited)
        XCTAssertEqual(TCCOutcome.from(authValue: 99), .unknown(rawValue: 99))
    }

    func testServiceFromKnownStrings() {
        XCTAssertEqual(TCCService.from(rawValue: "kTCCServiceCamera"), .camera)
        XCTAssertEqual(TCCService.from(rawValue: "kTCCServiceMicrophone"), .microphone)
        XCTAssertEqual(
            TCCService.from(rawValue: "kTCCServiceSystemPolicyAllFiles"),
            .fullDiskAccess
        )
        XCTAssertEqual(TCCService.from(rawValue: "kTCCServiceAccessibility"), .accessibility)
    }

    func testServicePreservesUnknownRawValue() {
        XCTAssertEqual(
            TCCService.from(rawValue: "kTCCServiceFuture"),
            .other(rawValue: "kTCCServiceFuture")
        )
        XCTAssertEqual(TCCService.from(rawValue: "kTCCServiceFuture").rawValue, "kTCCServiceFuture")
    }

    // MARK: - Event correlation against captured fixture

    func testBuildEventsRecoversCanonicalTransactions() throws {
        let entries = try loadFixtureEntries()
        let events = buildTCCEvents(from: entries)
        XCTAssertFalse(events.isEmpty,
                       "Fixture has multiple complete 6-line TCC transactions")
        for event in events {
            XCTAssertFalse(event.msgID.isEmpty)
            XCTAssertGreaterThan(event.timestamp.timeIntervalSince1970, 0)
        }
    }

    func testFixtureContainsWhatsAppCameraDenialChain() throws {
        // The captured fixture was recorded while WhatsApp was being
        // repeatedly denied camera access via ContinuityCaptureAgent.
        // This pin makes sure our correlation logic actually surfaces
        // that — it's the canonical "preflight denial chain" shape.
        let entries = try loadFixtureEntries()
        let events = buildTCCEvents(from: entries)
        let cameraDenials = events.filter { event in
            event.service == .camera
                && event.outcome == .denied
                && event.accessingProcess?.identifier == "net.whatsapp.WhatsApp"
        }
        XCTAssertFalse(cameraDenials.isEmpty,
                       "Fixture should contain WhatsApp camera denials")
        for denial in cameraDenials {
            XCTAssertEqual(denial.requestingProcess?.identifier,
                           "com.apple.cmio.ContinuityCaptureAgent")
            XCTAssertTrue(denial.isPreflight)
            XCTAssertFalse(denial.isDirectRequest,
                           "Brokered request — accessing != requesting")
        }
    }

    func testDirectRequestFlagForSameAccessingAndRequesting() {
        // Most contactsd-internal AUTHREQ_ATTRIBUTION lines have the
        // same process on both sides — those are direct requests.
        let process = TCCProcessRef(
            identifier: "com.apple.contactsd", pid: 43557, auid: 501, euid: 501,
            binaryPath: "/usr/libexec/contactsd"
        )
        let event = TCCEvent(
            timestamp: Date(), msgID: "1.1",
            service: .addressBook, isPreflight: true,
            accessingProcess: process, requestingProcess: process,
            outcome: .allowed, authValueRaw: 2, authReasonRaw: 0
        )
        XCTAssertTrue(event.isDirectRequest)
    }

    // MARK: - Robustness

    func testBuildEventsDropsTransactionsWithoutAuthreqCTX() {
        // Without AUTHREQ_CTX (no service captured), the transaction
        // has no detection value and should be dropped.
        let entries = [
            makeFixtureEntry(message: "REQUEST: msgID=999.1"),
            makeFixtureEntry(message: "REPLY: msgID=999.1, function=TCCAccessRequest")
        ]
        XCTAssertEqual(buildTCCEvents(from: entries).count, 0)
    }

    func testBuildEventsIgnoresNonTCCEntries() {
        let other = makeFixtureEntry(message: "Random kernel message", subsystem: "com.apple.something.else")
        XCTAssertEqual(buildTCCEvents(from: [other]).count, 0)
    }

    // MARK: - Helpers

    private func loadFixtureEntries() throws -> [LogEntry] {
        let testFile = URL(fileURLWithPath: #filePath)
        let fixturePath = testFile
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/log-show-sample.ndjson")
        let text = try String(contentsOf: fixturePath, encoding: .utf8)
        return parseLogShowNDJSON(text)
    }

    private func makeFixtureEntry(
        message: String,
        subsystem: String = "com.apple.TCC",
        category: String = "access"
    ) -> LogEntry {
        LogEntry(
            timestamp: Date(),
            processName: "tccd",
            processPath: "/System/Library/.../tccd",
            processID: 404,
            userID: 501,
            threadID: nil,
            subsystem: subsystem,
            category: category,
            level: .default,
            eventType: .log,
            message: message,
            activityID: 0
        )
    }
}
