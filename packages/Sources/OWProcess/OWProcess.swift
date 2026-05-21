import Darwin
import Foundation

/// Read-only metadata snapshot for a single running process.
///
/// `RunningProcess` is a value type; instances are immutable and reflect the
/// state of the OS process at the moment the snapshot was captured. Processes
/// that exit between snapshot and read time still appear in the value;
/// values do not auto-invalidate.
///
/// Optional fields (`arguments`, `openFiles`) follow the same three-state
/// convention:
///
/// - `nil` — the snapshot was taken without the corresponding `include*` flag.
/// - empty array — capture was requested but unavailable (system-protected
///   process, exited mid-snapshot, caller lacks permission).
/// - populated array — successful capture.
public struct RunningProcess: Sendable, Equatable, Hashable {
    public let pid: pid_t
    public let parentPid: pid_t
    public let name: String
    public let path: String?
    public let userId: uid_t
    public let arguments: [String]?
    public let openFiles: [OpenFile]?

    public init(
        pid: pid_t,
        parentPid: pid_t,
        name: String,
        path: String?,
        userId: uid_t,
        arguments: [String]? = nil,
        openFiles: [OpenFile]? = nil
    ) {
        self.pid = pid
        self.parentPid = parentPid
        self.name = name
        self.path = path
        self.userId = userId
        self.arguments = arguments
        self.openFiles = openFiles
    }
}

/// A single file descriptor held by a process.
///
/// The variant identifies the descriptor's underlying kernel object kind
/// (vnode, socket, pipe, etc.). Variant-specific metadata is captured where
/// it's cheap to obtain (path for vnodes, address family + socket type for
/// sockets); richer per-variant detail (socket peer endpoints, kqueue
/// registrations, etc.) is intentionally deferred to a later milestone.
public enum OpenFile: Sendable, Equatable, Hashable {
    /// A vnode-backed file descriptor (regular file, directory, symlink,
    /// device node). `path` is `nil` for anonymous vnodes or when the kernel
    /// declines to expose the path.
    case file(fd: Int32, path: String?)

    /// A socket. `family` is the address family (`AF_INET`, `AF_INET6`,
    /// `AF_UNIX`, etc.); `type` is the socket type (`SOCK_STREAM`,
    /// `SOCK_DGRAM`, ...). Peer endpoint details are deferred.
    case socket(fd: Int32, family: Int32, type: Int32)

    /// A pipe (one half of a pipe or fifo).
    case pipe(fd: Int32)

    /// Anything else — kqueue, POSIX shared memory, POSIX semaphore,
    /// fsevents, netpolicy, etc. The raw libproc fdtype value is preserved
    /// so callers that care can switch on it.
    case other(fd: Int32, rawType: Int32)

    /// The file descriptor number, regardless of variant.
    public var fd: Int32 {
        switch self {
        case .file(let fd, _), .socket(let fd, _, _), .pipe(let fd), .other(let fd, _):
            return fd
        }
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
    /// - Parameter includeOpenFiles: when `true`, also capture each process's
    ///   open file descriptors via `proc_pidinfo(PROC_PIDLISTFDS)` plus a
    ///   variant-specific `proc_pidfdinfo` call per FD. Adds multiple
    ///   syscalls per process; only enable when the caller actually needs
    ///   the FD table.
    public static func all(
        includeArguments: Bool = false,
        includeOpenFiles: Bool = false
    ) throws -> [RunningProcess] {
        let pids = try listAllPids()
        return pids.compactMap { pid in
            try? snapshot(
                pid: pid,
                includeArguments: includeArguments,
                includeOpenFiles: includeOpenFiles
            )
        }
    }

    /// Snapshot a single process by PID.
    ///
    /// Throws `OWProcessError.metadataUnavailable` when the process does not
    /// exist or the caller cannot read its metadata. Use `try?` at the call
    /// site when iterating over PIDs returned by `all()` — process churn
    /// during enumeration is expected.
    ///
    /// - Parameter includeArguments: see `all(includeArguments:includeOpenFiles:)`.
    /// - Parameter includeOpenFiles: see `all(includeArguments:includeOpenFiles:)`.
    public static func snapshot(
        pid: pid_t,
        includeArguments: Bool = false,
        includeOpenFiles: Bool = false
    ) throws -> RunningProcess {
        let info = try fetchBSDInfo(pid: pid)
        let path = fetchPath(pid: pid)
        let name = readNullTerminated(bytes: info.pbi_name)
            ?? readNullTerminated(bytes: info.pbi_comm)
            ?? ""
        let arguments = includeArguments ? (fetchArguments(pid: pid) ?? []) : nil
        let openFiles = includeOpenFiles ? (fetchOpenFiles(pid: pid) ?? []) : nil
        return RunningProcess(
            pid: pid,
            parentPid: pid_t(info.pbi_ppid),
            name: name,
            path: path,
            userId: info.pbi_uid,
            arguments: arguments,
            openFiles: openFiles
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

// MARK: - libproc bridging (PROC_PIDLISTFDS → [OpenFile])

// Constants from <sys/proc_info.h>. Inlined because Swift's C macro importer
// can't always evaluate them; matched against the SDK header values.
private let proxFdtypeVnode: Int32 = 1
private let proxFdtypeSocket: Int32 = 2
private let proxFdtypePipe: Int32 = 6

/// Enumerates open file descriptors for a process.
///
/// First call: `proc_pidinfo(PROC_PIDLISTFDS)` returns the list of
/// (fd, fdtype) pairs as packed `proc_fdinfo` structs. The second call set
/// — one `proc_pidfdinfo` per FD with a variant-specific flavor — fills in
/// path / family / type details.
///
/// Returns `nil` when the initial `proc_pidinfo` call fails (caller lacks
/// permission, process exited). Returns an empty array when the process is
/// alive but holds zero descriptors (rare but legal — e.g., kernel tasks).
private func fetchOpenFiles(pid: pid_t) -> [OpenFile]? {
    let stride = MemoryLayout<proc_fdinfo>.stride
    let listSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
    guard listSize > 0 else { return nil }

    let fdCount = Int(listSize) / stride
    var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: fdCount)
    let actualSize = fds.withUnsafeMutableBufferPointer { buf in
        proc_pidinfo(pid, PROC_PIDLISTFDS, 0, buf.baseAddress, Int32(buf.count * stride))
    }
    guard actualSize > 0 else { return nil }

    let actualCount = Int(actualSize) / stride
    var result: [OpenFile] = []
    result.reserveCapacity(actualCount)
    for entry in fds.prefix(actualCount) {
        let fd = entry.proc_fd
        let fdtype = Int32(bitPattern: entry.proc_fdtype)
        result.append(openFile(pid: pid, fd: fd, fdtype: fdtype))
    }
    return result
}

private func openFile(pid: pid_t, fd: Int32, fdtype: Int32) -> OpenFile {
    switch fdtype {
    case proxFdtypeVnode:
        return .file(fd: fd, path: fetchVnodePath(pid: pid, fd: fd))
    case proxFdtypeSocket:
        let info = fetchSocketInfo(pid: pid, fd: fd)
        return .socket(fd: fd, family: info?.family ?? 0, type: info?.type ?? 0)
    case proxFdtypePipe:
        return .pipe(fd: fd)
    default:
        return .other(fd: fd, rawType: fdtype)
    }
}

private func fetchVnodePath(pid: pid_t, fd: Int32) -> String? {
    var info = vnode_fdinfowithpath()
    let size = withUnsafeMutablePointer(to: &info) { ptr in
        proc_pidfdinfo(pid, fd, PROC_PIDFDVNODEPATHINFO, ptr, Int32(MemoryLayout<vnode_fdinfowithpath>.size))
    }
    guard size == MemoryLayout<vnode_fdinfowithpath>.size else { return nil }
    return readNullTerminated(bytes: info.pvip.vip_path)
}

private struct SocketBasics {
    let family: Int32
    let type: Int32
}

private func fetchSocketInfo(pid: pid_t, fd: Int32) -> SocketBasics? {
    var info = socket_fdinfo()
    let size = withUnsafeMutablePointer(to: &info) { ptr in
        proc_pidfdinfo(pid, fd, PROC_PIDFDSOCKETINFO, ptr, Int32(MemoryLayout<socket_fdinfo>.size))
    }
    guard size == MemoryLayout<socket_fdinfo>.size else { return nil }
    return SocketBasics(
        family: info.psi.soi_family,
        type: info.psi.soi_type
    )
}
