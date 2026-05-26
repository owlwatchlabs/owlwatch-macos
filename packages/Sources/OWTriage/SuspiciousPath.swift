import Foundation

/// Path prefixes considered suspicious for code-execution origin.
/// Tunable, deliberately small list — every entry is a "this is
/// almost never where legitimate software runs from" claim.
///
/// Adding here is a per-user-deploy decision: a developer's
/// `~/.cargo/`, `~/.rbenv/`, `~/.local/` are technically in scope
/// (we flag `~/.local/`), and a server deploy might want to add
/// `/var/tmp/.X11-unix/` or similar. Treat this list as a starting
/// point, not exhaustive.
public let suspiciousPrefixes: [String] = [
    "/tmp/",
    "/private/tmp/",
    "/private/var/tmp/",
    "/var/tmp/"
]

/// `true` when the given executable path looks suspicious. Returns
/// `false` for `nil` (no path captured) — absence is not suspicion.
///
/// Rules (in order):
/// 1. Path starts with any prefix in `suspiciousPrefixes`.
/// 2. Path contains a `/.` segment (hidden file or hidden dir
///    anywhere in the chain — `/Users/x/.cache/loader` and
///    `/var/folders/.../.cache/foo` both match).
/// 3. Path lives under `~/Library/` or `~/.local/` — both are
///    user-writable execution origins less common than
///    `/Applications/`.
public func isSuspiciousPath(_ path: String?) -> Bool {
    guard let path else { return false }

    for prefix in suspiciousPrefixes where path.hasPrefix(prefix) {
        return true
    }
    if path.contains("/.") {
        return true
    }
    let home = NSHomeDirectory()
    if path.hasPrefix(home + "/Library/") { return true }
    if path.hasPrefix(home + "/.local/") { return true }
    return false
}
