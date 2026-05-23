import Foundation
@testable import OWLog
import XCTest

final class LogStreamTests: XCTestCase {
    // MARK: - Stream argv builder

    func testStreamArgvBaseShape() {
        let argv = buildLogStreamArguments(for: LogQuery())
        XCTAssertEqual(argv, ["stream", "--style", "ndjson"],
                       "Empty query should produce the bare minimum argv — no level or predicate flags")
    }

    func testStreamArgvOmitsHistoricalOptions() {
        // log stream rejects --start / --end / --last; the builder
        // must silently drop them even when the LogQuery sets them.
        var query = LogQuery()
        query.since = Date()
        query.until = Date()
        query.limit = 500
        let argv = buildLogStreamArguments(for: query)
        XCTAssertFalse(argv.contains("--start"),
                       "log stream rejects --start; must not appear in argv")
        XCTAssertFalse(argv.contains("--end"),
                       "log stream rejects --end; must not appear in argv")
        XCTAssertFalse(argv.contains("--last"),
                       "log stream rejects --last; must not appear in argv")
    }

    func testStreamArgvIncludesLevelFlags() {
        let argv = buildLogStreamArguments(for: LogQuery(includeInfo: true, includeDebug: true))
        XCTAssertTrue(argv.contains("--info"))
        XCTAssertTrue(argv.contains("--debug"))
    }

    func testStreamArgvEmbedsPredicate() {
        let argv = buildLogStreamArguments(for: LogQuery(subsystem: "com.apple.TCC"))
        guard let predicateIndex = argv.firstIndex(of: "--predicate") else {
            return XCTFail("Expected --predicate in stream argv when subsystem is set")
        }
        XCTAssertEqual(argv[argv.index(after: predicateIndex)],
                       "subsystem == \"com.apple.TCC\"")
    }

    // MARK: - LineBuffer

    func testLineBufferYieldsCompleteLines() {
        let buffer = LineBuffer()
        let lines = buffer.consume(Data("first line\nsecond line\nthird".utf8))
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(String(data: lines[0], encoding: .utf8), "first line")
        XCTAssertEqual(String(data: lines[1], encoding: .utf8), "second line")
    }

    func testLineBufferHoldsTrailingPartialUntilNextChunk() {
        let buffer = LineBuffer()
        let firstChunk = buffer.consume(Data("partial".utf8))
        XCTAssertEqual(firstChunk.count, 0, "Partial line should stay buffered")

        let secondChunk = buffer.consume(Data(" continues\nnext".utf8))
        XCTAssertEqual(secondChunk.count, 1)
        XCTAssertEqual(String(data: secondChunk[0], encoding: .utf8),
                       "partial continues",
                       "Buffer should stitch partial + continuation into one line")
    }

    func testLineBufferSkipsEmptyLines() {
        let buffer = LineBuffer()
        let lines = buffer.consume(Data("\n\n\na\n".utf8))
        XCTAssertEqual(lines.count, 1, "Empty lines should be discarded")
        XCTAssertEqual(String(data: lines[0], encoding: .utf8), "a")
    }

    func testLineBufferAcrossManySmallChunks() {
        // Simulate worst-case: stdout reads coming back one byte at a time.
        let buffer = LineBuffer()
        var lines: [Data] = []
        for byte in Data("hello\nworld\n".utf8) {
            let chunk = Data([byte])
            lines.append(contentsOf: buffer.consume(chunk))
        }
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(String(data: lines[0], encoding: .utf8), "hello")
        XCTAssertEqual(String(data: lines[1], encoding: .utf8), "world")
    }

    // MARK: - Live-stream integration smoke

    // Deliberately NOT included: a test that actually spawns `log stream`
    // and consumes the AsyncStream. `log show` subprocess behavior under
    // XCTest was already observed to be non-deterministic (M5.2 / M6.1);
    // `log stream` is worse — it never exits on its own, and any kill
    // timing depends on launchd. The argv builder + LineBuffer tests
    // above cover everything that's deterministic; the live path is
    // exercised through `owlwatch logs --follow` manually.
}
