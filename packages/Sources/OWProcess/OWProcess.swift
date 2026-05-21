import Darwin
import Foundation

/// Read-only metadata snapshot for a single running process.
///
/// `RunningProcess` is a value type; instances are immutable and reflect the
/// state of the OS process at the moment the snapshot was captured. Processes
/// that exit between snapshot and read time still appear in the value;
/// values do not auto-invalidate.
///
/// `arguments` is `nil` when the snapshot was captured without
/// `includeArguments`, and an empty array when arguments were requested but
/// could not be read (system-protected process, exited mid-snapshot, caller
/// lacks permission). It is an array of strings when arguments were
/// successfully captured; `arguments[0]` is the process's `argv[0]`, which
/// is conventionally the executable path or invocation name.
public struct RunningProcess: Sendable, Equatable, Hashable {
    public let pid: pid_t
    public let parentPid: pid_t
    public let name: String
    public let path: String?
    public let userId: uid_t
    public let arguments: [String]?

    public init(
        pid: pid_t,
        parentPid: pid_t,
        name: String,
        path: String?,
        userId: uid_t,
        arguments: [String]? = nil
    ) {
        self.pid = pid
        self.parentPid = parentPid
        self.name = name
        self.path = path
        self.userId = userId
        self.arguments = arguments
    }
}

public enum OWProcessError: Error, Sendable, Equatable {
    /// The host's process table could not be enumerated. Indicates a libproc
    /// failure or a misconfigured runtime; the caller has no reasonable recovery.
    case enumerationFailed

    /// The named PID could not be inspected. Common reasons: the process has
    /// exited between enumeration and snapshot, the process is protected
    /// (system or other-user), or the caller lacks permission.
    case metadataUnavailable(pid: pid_t)
}

public enum OWProcess {
    /// Snapshot every process visible to the current user.
    ///
    /// Uses libproc's `proc_listpids` to enumerate, then `proc_pidinfo` per
    /// PID to capture metadata. Processes the caller cannot inspect — other
    /// users' processes when running unprivileged, processes that exited
    /// between enumeration and snapshot — are silently skipped. The returned
    /// array represents the caller's view of the process table, not the
    /// host's complete process table.
    ///
    /// - Parameter includeArguments: when `true`, also capture each process's
    ///   `argv` via `sysctl(KERN_PROCARGS2)`. Arguments are unavailable for
    ///   other-user / SIP-protected processes when running unprivileged; the
    ///   `arguments` field is set to an empty array in that case. Default is
    ///   `false`; capturing arguments adds one sysctl call per process and
    ///   roughly doubles the snapshot cost on typical hosts.
    public static func all(includeArguments: Bool = false) throws -> [RunningProcess] {
        let pids = try listAllPids()
        return pids.compactMap { try? snapshot(pid: $0, includeArguments: includeArguments) }
    }

    /// Snapshot a single process by PID.
    ///
    /// Throws `OWProcessError.metadataUnavailable` when the process does not
    /// exist or the caller cannot read its metadata. Use `try?` at the call
    /// site when iterating over PIDs returned by `all()` — process churn
    /// during enumeration is expected.
    ///
    /// - Parameter includeArguments: see `all(includeArguments:)`.
    public static func snapshot(pid: pid_t, includeArguments: Bool = false) throws -> RunningProcess {
        let info = try fetchBSDInfo(pid: pid)
        let path = fetchPath(pid: pid)
        let name = readNullTerminated(bytes: info.pbi_name)
            ?? readNullTerminated(bytes: info.pbi_comm)
            ?? ""
        let arguments = includeArguments ? (fetchArguments(pid: pid) ?? []) : nil
        return RunningProcess(
            pid: pid,
            parentPid: pid_t(info.pbi_ppid),
            name: name,
            path: path,
            userId: info.pbi_uid,
            arguments: arguments
        )
    }
}

// MARK: - libproc bridging

private func listAllPids() throws -> [pid_t] {
    let bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
    guard bufferSize > 0 else { throw OWProcessError.enumerationFailed }

    let pidCount = Int(bufferSize) / MemoryLayout<pid_t>.size
    var pids = [pid_t](repeating: 0, count: pidCount)
    let writtenBytes = pids.withUnsafeMutableBufferPointer { buf in
        proc_listpids(UInt32(PROC_ALL_PIDS), 0, buf.baseAddress, bufferSize)
    }
    guard writtenBytes > 0 else { throw OWProcessError.enumerationFailed }

    let writtenCount = Int(writtenBytes) / MemoryLayout<pid_t>.size
    return pids.prefix(writtenCount).filter { $0 != 0 }
}

private func fetchBSDInfo(pid: pid_t) throws -> proc_bsdinfo {
    var info = proc_bsdinfo()
    let size = withUnsafeMutablePointer(to: &info) { ptr in
        proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, ptr, Int32(MemoryLayout<proc_bsdinfo>.size))
    }
    guard size == MemoryLayout<proc_bsdinfo>.size else {
        throw OWProcessError.metadataUnavailable(pid: pid)
    }
    return info
}

// PROC_PIDPATHINFO_MAXSIZE in <sys/proc_info.h> expands to `4 * MAXPATHLEN`,
// which Swift's C macro importer cannot evaluate. Inline the resulting value
// (4 * 1024 = 4096) — the actual buffer size proc_pidpath wants.
private let procPidPathInfoMaxSize: Int = 4096

private func fetchPath(pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: procPidPathInfoMaxSize)
    let length = buffer.withUnsafeMutableBufferPointer { buf -> Int32 in
        proc_pidpath(pid, buf.baseAddress, UInt32(buf.count))
    }
    guard length > 0 else { return nil }
    // `length` is the number of bytes proc_pidpath wrote, not including the
    // null terminator. macOS paths are UTF-8; the validating initializer
    // returns nil if the kernel ever returned bytes that aren't a path.
    let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
    return String(bytes: bytes, encoding: .utf8)
}

private func readNullTerminated<T>(bytes tuple: T) -> String? {
    let decoded = withUnsafeBytes(of: tuple) { rawBytes -> String? in
        let untilNull: [UInt8] = rawBytes.prefix(while: { $0 != 0 }).map { $0 }
        return String(bytes: untilNull, encoding: .utf8)
    }
    guard let decoded, !decoded.isEmpty else { return nil }
    return decoded
}

// MARK: - sysctl bridging (KERN_PROCARGS2 → argv[])

/// Fetches `argv` for a process via `sysctl(KERN_PROCARGS2)`.
///
/// Returns `nil` on sysctl failure (process doesn't exist, caller lacks
/// permission, kernel returned an unexpected layout). Returns an empty
/// array when sysctl succeeded but the kernel reported `argc == 0` (rare;
/// typically only for the kernel itself).
///
/// Buffer layout (per `<sys/sysctl.h>` and observation):
///
///     [argc: Int32]                      // 4 bytes, native byte order
///     [exec_path: null-terminated cstr]  // variable length
///     [zero padding: 0..n bytes of 0x00]
///     [argv[0]: null-terminated cstr]
///     [argv[1]: null-terminated cstr]
///     ...
///     [argv[argc-1]: null-terminated cstr]
///     [envp[0]: null-terminated cstr]
///     ...
///
/// The parser reads `argc`, skips the exec_path and trailing zero padding,
/// then reads exactly `argc` null-terminated strings.
private func fetchArguments(pid: pid_t) -> [String]? {
    let argMax = queryArgMax() ?? 1 << 20  // 1 MiB fallback
    var buffer = [UInt8](repeating: 0, count: argMax)
    var bufferSize = argMax
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]

    let result = buffer.withUnsafeMutableBufferPointer { buf in
        sysctl(&mib, UInt32(mib.count), buf.baseAddress, &bufferSize, nil, 0)
    }
    guard result == 0, bufferSize >= MemoryLayout<Int32>.size else {
        return nil
    }

    var argc: Int32 = 0
    buffer.withUnsafeBufferPointer { ptr in
        _ = memcpy(&argc, ptr.baseAddress, MemoryLayout<Int32>.size)
    }
    guard argc > 0 else { return [] }

    // Skip argc (4 bytes) + exec_path (cstr) + trailing zero padding.
    var offset = MemoryLayout<Int32>.size
    while offset < bufferSize, buffer[offset] != 0 {
        offset += 1
    }
    while offset < bufferSize, buffer[offset] == 0 {
        offset += 1
    }

    var args: [String] = []
    args.reserveCapacity(Int(argc))
    for _ in 0..<argc {
        guard offset < bufferSize else { break }
        let start = offset
        while offset < bufferSize, buffer[offset] != 0 {
            offset += 1
        }
        // Lossy decode is intentional here: argv occasionally carries binary
        // payloads (rare, but a single garbled byte should not drop the whole
        // arg). The failable String(bytes:encoding:) form would discard the
        // entire argument on any invalid UTF-8.
        // swiftlint:disable:next optional_data_string_conversion
        args.append(String(decoding: buffer[start..<offset], as: UTF8.self))
        offset += 1  // step past the null terminator
    }

    return args
}

private func queryArgMax() -> Int? {
    var argMax: Int32 = 0
    var size = MemoryLayout<Int32>.size
    var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
    let result = sysctl(&mib, UInt32(mib.count), &argMax, &size, nil, 0)
    guard result == 0, argMax > 0 else { return nil }
    return Int(argMax)
}
