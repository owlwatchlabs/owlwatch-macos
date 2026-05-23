import Foundation

extension OWLog {
    /// Live-tail the unified log archive. Returns an `AsyncThrowingStream`
    /// that yields one ``LogEntry`` per `log stream --style ndjson`
    /// line. The subprocess runs until the stream is cancelled (caller
    /// breaks out of the `for await` loop, the parent `Task` is
    /// cancelled, or the host process exits).
    ///
    /// `log stream` is the live counterpart to `log show`. It only
    /// emits records forward in time — `query.since` / `query.until` /
    /// `query.limit` are ignored because they don't apply to a live
    /// stream. The level (`includeInfo` / `includeDebug`) and the
    /// predicate fields work the same.
    ///
    /// Cancellation: the stream's `onTermination` handler calls
    /// `process.terminate()` (SIGTERM). `log stream` exits cleanly on
    /// SIGTERM; if it ever stops doing so, callers should also
    /// `process.interrupt()` as a follow-up.
    public static func stream(_ query: LogQuery = LogQuery()) -> AsyncThrowingStream<LogEntry, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            process.arguments = buildLogStreamArguments(for: query)
            let stdoutPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = Pipe()  // discard banner output

            continuation.onTermination = { _ in
                if process.isRunning {
                    process.terminate()
                }
            }

            // Buffer for incomplete trailing lines between read chunks.
            // log stream emits one JSON object per newline, but reads
            // come in arbitrary byte chunks.
            let lineBuffer = LineBuffer()
            let decoder = JSONDecoder()
            let formatter = makeLogShowTimestampFormatter()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    continuation.finish()
                    return
                }
                for line in lineBuffer.consume(chunk) {
                    guard
                        let raw = try? decoder.decode(LogShowRecord.self, from: line),
                        let entry = buildLogEntry(from: raw, formatter: formatter)
                    else { continue }
                    continuation.yield(entry)
                }
            }

            process.terminationHandler = { _ in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                continuation.finish()
            }

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: OWLogError.logShowFailed(
                    exitCode: -1,
                    stderr: "failed to spawn /usr/bin/log stream: \(error.localizedDescription)"
                ))
            }
        }
    }
}

// MARK: - argv

/// Build the argv for `/usr/bin/log stream`. Differs from
/// ``buildLogShowArguments(for:)`` only in the leading subcommand and
/// the absence of `--start` / `--end` / `--last` (none of which `log
/// stream` accepts).
internal func buildLogStreamArguments(for query: LogQuery) -> [String] {
    var argv: [String] = ["stream", "--style", "ndjson"]
    if query.includeInfo { argv.append("--info") }
    if query.includeDebug { argv.append("--debug") }
    if let predicate = buildPredicate(for: query) {
        argv.append("--predicate")
        argv.append(predicate)
    }
    return argv
}

// MARK: - Line buffer

/// Accumulates bytes from chunked stdout reads and yields complete
/// newline-terminated lines as `Data`. Internal because there's no
/// reason to expose it.
///
/// Marked `@unchecked Sendable` because Foundation serializes all
/// invocations of a `Pipe.fileHandleForReading.readabilityHandler`
/// onto a single dispatch queue — so the only writer touching
/// `pending` at any moment is the current handler invocation.
internal final class LineBuffer: @unchecked Sendable {
    private var pending = Data()

    /// Append `chunk` and return every complete line newly available
    /// (without the trailing `\n`). Any partial trailing line stays
    /// in the internal buffer until the next call.
    func consume(_ chunk: Data) -> [Data] {
        pending.append(chunk)
        var lines: [Data] = []
        while let newlineIndex = pending.firstIndex(of: 0x0A) {
            let line = pending[pending.startIndex..<newlineIndex]
            pending.removeSubrange(pending.startIndex...newlineIndex)
            if !line.isEmpty {
                lines.append(Data(line))
            }
        }
        return lines
    }
}
