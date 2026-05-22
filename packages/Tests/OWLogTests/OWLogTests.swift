import Foundation
@testable import OWLog
import XCTest

final class OWLogTests: XCTestCase {
    // MARK: - LogLevel mapping

    func testLogLevelFromKnownStrings() {
        XCTAssertEqual(LogLevel.from(rawValue: "Default"), .default)
        XCTAssertEqual(LogLevel.from(rawValue: "Info"), .info)
        XCTAssertEqual(LogLevel.from(rawValue: "Debug"), .debug)
        XCTAssertEqual(LogLevel.from(rawValue: "Error"), .error)
        XCTAssertEqual(LogLevel.from(rawValue: "Fault"), .fault)
    }

    func testLogLevelUnknownFallsBackToDefault() {
        XCTAssertEqual(LogLevel.from(rawValue: "MadeUpLevel"), .default)
        XCTAssertEqual(LogLevel.from(rawValue: ""), .default)
    }

    // MARK: - LogEventType mapping

    func testLogEventTypeKnownValues() {
        XCTAssertEqual(LogEventType.from(rawValue: "logEvent"), .log)
        XCTAssertEqual(LogEventType.from(rawValue: "stateEvent"), .state)
        XCTAssertEqual(LogEventType.from(rawValue: "signpostEvent"), .signpost)
        XCTAssertEqual(LogEventType.from(rawValue: "userActionEvent"), .userAction)
        XCTAssertEqual(LogEventType.from(rawValue: "traceEvent"), .trace)
    }

    func testLogEventTypeUnknownPreservesRawValue() {
        XCTAssertEqual(
            LogEventType.from(rawValue: "futureKindOfEvent"),
            .other(rawValue: "futureKindOfEvent")
        )
        XCTAssertEqual(
            LogEventType.from(rawValue: "futureKindOfEvent").rawValue,
            "futureKindOfEvent"
        )
    }

    // MARK: - Predicate builder

    func testPredicateBuilderEmptyQueryReturnsNil() {
        XCTAssertNil(buildPredicate(for: LogQuery()))
    }

    func testPredicateBuilderSingleSubsystem() {
        let predicate = buildPredicate(for: LogQuery(subsystem: "com.apple.TCC"))
        XCTAssertEqual(predicate, "subsystem == \"com.apple.TCC\"")
    }

    func testPredicateBuilderAndsMultipleClauses() {
        let query = LogQuery(
            subsystem: "com.apple.TCC",
            process: "tccd",
            messageContains: "denied"
        )
        let predicate = buildPredicate(for: query)
        // Order is stable: subsystem, category, process, messageContains, free-form predicate.
        XCTAssertEqual(
            predicate,
            "subsystem == \"com.apple.TCC\" AND process == \"tccd\" "
            + "AND eventMessage CONTAINS \"denied\""
        )
    }

    func testPredicateBuilderEscapesEmbeddedQuotes() throws {
        let query = LogQuery(messageContains: #"with "quotes""#)
        let predicate = try XCTUnwrap(buildPredicate(for: query))
        // Embedded `"` becomes `\"` so the outer string literal stays valid.
        XCTAssertTrue(predicate.contains(#"\""#))
        XCTAssertFalse(predicate.contains(#"with "quotes""#),
                       "Unescaped quotes would break the NSPredicate parser")
    }

    func testPredicateBuilderAppendsFreeFormPredicate() {
        let query = LogQuery(subsystem: "com.apple.TCC", predicate: "processID == 1234")
        let predicate = buildPredicate(for: query)
        XCTAssertEqual(
            predicate,
            "subsystem == \"com.apple.TCC\" AND (processID == 1234)"
        )
    }

    // MARK: - Argument builder

    func testArgvBuilderDefaultsUseLastLimit() {
        let argv = buildLogShowArguments(for: LogQuery())
        XCTAssertEqual(argv.prefix(3), ["show", "--style", "ndjson"])
        XCTAssertTrue(argv.contains("--last"))
        XCTAssertTrue(argv.contains(String(LogQuery.defaultLimit)))
        XCTAssertFalse(argv.contains("--start"))
        XCTAssertFalse(argv.contains("--end"))
        XCTAssertFalse(argv.contains("--info"))
        XCTAssertFalse(argv.contains("--debug"))
    }

    func testArgvBuilderTimeRangeSuppressesLast() {
        let since = Date()
        let query = LogQuery(since: since)
        let argv = buildLogShowArguments(for: query)
        XCTAssertTrue(argv.contains("--start"))
        XCTAssertFalse(argv.contains("--last"),
                       "--last conflicts with --start; should be omitted when a time range is given")
    }

    func testArgvBuilderIncludesInfoAndDebugFlags() {
        let argv = buildLogShowArguments(for: LogQuery(includeInfo: true, includeDebug: true))
        XCTAssertTrue(argv.contains("--info"))
        XCTAssertTrue(argv.contains("--debug"))
    }

    func testArgvBuilderEmbedsPredicate() {
        let query = LogQuery(subsystem: "com.apple.TCC")
        let argv = buildLogShowArguments(for: query)
        guard let predicateIndex = argv.firstIndex(of: "--predicate") else {
            return XCTFail("Expected --predicate in argv")
        }
        XCTAssertEqual(argv[argv.index(after: predicateIndex)],
                       "subsystem == \"com.apple.TCC\"")
    }

    // MARK: - NDJSON parser against captured fixture

    func testParserAgainstCapturedFixture() throws {
        let fixture = try loadFixture()
        let entries = parseLogShowNDJSON(fixture)
        XCTAssertFalse(entries.isEmpty,
                       "Captured fixture should yield at least one parseable entry")
    }

    func testParserExtractsTCCAccessRecord() throws {
        let fixture = try loadFixture()
        let entries = parseLogShowNDJSON(fixture)
        guard let tcc = entries.first(where: { $0.subsystem == "com.apple.TCC" }) else {
            return XCTFail("Fixture should contain at least one com.apple.TCC entry")
        }
        XCTAssertEqual(tcc.processName, "tccd",
                       "TCC records originate from /System/Library/PrivateFrameworks/.../tccd")
        XCTAssertEqual(tcc.category, "access")
        XCTAssertEqual(tcc.eventType, .log)
        XCTAssertFalse(tcc.message.isEmpty)
        XCTAssertNotNil(tcc.processID)
        XCTAssertNotNil(tcc.userID)
    }

    func testParserSkipsBlankAndInvalidLines() {
        let mixed = """
        { "timestamp": "2026-05-22 17:00:00.000000-0300", "eventMessage": "first", "messageType": "Default" }
        this is not json

        { "timestamp": "2026-05-22 17:00:01.000000-0300", "eventMessage": "second", "messageType": "Info" }
        """
        let entries = parseLogShowNDJSON(mixed)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].message, "first")
        XCTAssertEqual(entries[1].message, "second")
    }

    func testParserSkipsRecordsWithUnparseableTimestamp() {
        let badTimestamp = #"""
        { "timestamp": "tomorrow", "eventMessage": "nope", "messageType": "Default" }
        """#
        XCTAssertEqual(parseLogShowNDJSON(badTimestamp).count, 0,
                       "A record whose timestamp doesn't parse should be silently dropped")
    }

    func testParserHandlesLargeUIDValuesWithoutCrashing() {
        // UID -2 ("nobody") is encoded as 4294967294 — overflows Int32.
        // truncatingIfNeeded in the parser keeps us from crashing.
        let nobody = #"{"timestamp":"2026-05-22 17:00:00.000000-0300","#
            + #""eventMessage":"x","messageType":"Default","#
            + #""userID":4294967294,"processID":0}"#
        let entries = parseLogShowNDJSON(nobody)
        XCTAssertEqual(entries.count, 1)
        XCTAssertNotNil(entries[0].userID)
    }

    // MARK: - Helpers

    private func loadFixture() throws -> String {
        // #filePath is always absolute under SwiftPM, unlike #file which
        // can be virtualized to a relative path.
        let testFile = URL(fileURLWithPath: #filePath)
        let path = testFile
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/log-show-sample.ndjson")
        return try String(contentsOf: path, encoding: .utf8)
    }
}
