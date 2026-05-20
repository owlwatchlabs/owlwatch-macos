import Darwin

/// Read-only metadata snapshot for a single running process.
///
/// `RunningProcess` is a value type; instances are immutable and reflect the
/// state of the OS process at the moment the snapshot was captured. Processes
/// that exit between snapshot and read time still appear in the value;
/// values do not auto-invalidate.
public struct RunningProcess: Sendable, Equatable, Hashable {
    public let pid: pid_t
    public let parentPid: pid_t
    public let name: String
    public let path: String?
    public let userId: uid_t

    public init(pid: pid_t, parentPid: pid_t, name: String, path: String?, userId: uid_t) {
        self.pid = pid
        self.parentPid = parentPid
        self.name = name
        self.path = path
        self.userId = userId
    }
}

public enum NWProcessError: Error, Sendable, Equatable {
    /// The host's process table could not be enumerated. Indicates a libproc
    /// failure or a misconfigured runtime; the caller has no reasonable recovery.
    case enumerationFailed

    /// The named PID could not be inspected. Common reasons: the process has
    /// exited between enumeration and snapshot, the process is protected
    /// (system or other-user), or the caller lacks permission.
    case metadataUnavailable(pid: pid_t)
}

public enum NWProcess {
    /// Snapshot every process visible to the current user.
    ///
    /// Uses libproc's `proc_listpids` to enumerate, then `proc_pidinfo` per
    /// PID to capture metadata. Processes the caller cannot inspect — other
    /// users' processes when running unprivileged, processes that exited
    /// between enumeration and snapshot — are silently skipped. The returned
    /// array represents the caller's view of the process table, not the
    /// host's complete process table.
    public static func all() throws -> [RunningProcess] {
        let pids = try listAllPids()
        return pids.compactMap { try? snapshot(pid: $0) }
    }

    /// Snapshot a single process by PID.
    ///
    /// Throws `NWProcessError.metadataUnavailable` when the process does not
    /// exist or the caller cannot read its metadata. Use `try?` at the call
    /// site when iterating over PIDs returned by `all()` — process churn
    /// during enumeration is expected.
    public static func snapshot(pid: pid_t) throws -> RunningProcess {
        let info = try fetchBSDInfo(pid: pid)
        let path = fetchPath(pid: pid)
        let name = readNullTerminated(bytes: info.pbi_name)
            ?? readNullTerminated(bytes: info.pbi_comm)
            ?? ""
        return RunningProcess(
            pid: pid,
            parentPid: pid_t(info.pbi_ppid),
            name: name,
            path: path,
            userId: info.pbi_uid
        )
    }
}

// MARK: - libproc bridging

private func listAllPids() throws -> [pid_t] {
    let bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
    guard bufferSize > 0 else { throw NWProcessError.enumerationFailed }

    let pidCount = Int(bufferSize) / MemoryLayout<pid_t>.size
    var pids = [pid_t](repeating: 0, count: pidCount)
    let writtenBytes = pids.withUnsafeMutableBufferPointer { buf in
        proc_listpids(UInt32(PROC_ALL_PIDS), 0, buf.baseAddress, bufferSize)
    }
    guard writtenBytes > 0 else { throw NWProcessError.enumerationFailed }

    let writtenCount = Int(writtenBytes) / MemoryLayout<pid_t>.size
    return pids.prefix(writtenCount).filter { $0 != 0 }
}

private func fetchBSDInfo(pid: pid_t) throws -> proc_bsdinfo {
    var info = proc_bsdinfo()
    let size = withUnsafeMutablePointer(to: &info) { ptr in
        proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, ptr, Int32(MemoryLayout<proc_bsdinfo>.size))
    }
    guard size == MemoryLayout<proc_bsdinfo>.size else {
        throw NWProcessError.metadataUnavailable(pid: pid)
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
    return String(cString: buffer)
}

private func readNullTerminated<T>(bytes tuple: T) -> String? {
    let string = withUnsafeBytes(of: tuple) { rawBytes -> String in
        let cBytes = rawBytes.bindMemory(to: CChar.self)
        return cBytes.baseAddress.map { String(cString: $0) } ?? ""
    }
    return string.isEmpty ? nil : string
}
