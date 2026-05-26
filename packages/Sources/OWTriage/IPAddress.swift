import Foundation

/// Minimal IPv4/IPv6 parser + range-check helpers used by
/// ``NetworkScope``. Internal-only — the surface the engine needs
/// is "given a remoteAddress string, is it loopback / private / link-
/// local / unique-local / something else?". Network.framework's
/// `IPv4Address` / `IPv6Address` are not used here so the module
/// stays buildable on every Apple platform without dragging an
/// extra link dependency.
///
/// IPv4 parsing accepts the dotted-decimal form (`192.168.1.1`).
/// IPv6 parsing accepts the colon-hex form with optional `::`
/// compression. v4-mapped v6 (`::ffff:1.2.3.4`) is not supported —
/// `OWNetwork` doesn't emit it.
enum IPAddress: Equatable {
    case v4(UInt32)
    case v6([UInt16])  // 8 groups of 16 bits

    init?(_ string: String) {
        if let v4 = Self.parseV4(string) { self = .v4(v4); return }
        if let v6 = Self.parseV6(string) { self = .v6(v6); return }
        return nil
    }

    // MARK: - Range predicates

    /// 127.0.0.0/8 (IPv4) or ::1 (IPv6).
    var isLoopback: Bool {
        switch self {
        case .v4(let value):
            return (value >> 24) == 127
        case .v6(let groups):
            // ::1 → seven leading zero groups + 0x0001
            return groups.count == 8
                && groups.prefix(7).allSatisfy { $0 == 0 }
                && groups[7] == 1
        }
    }

    /// RFC 1918 v4 private blocks (10/8, 172.16/12, 192.168/16).
    /// Also classifies IPv6 unique-local (fc00::/7) here for the
    /// caller's convenience — semantically "the LAN".
    var isPrivate: Bool {
        switch self {
        case .v4(let value):
            let firstOctet = (value >> 24) & 0xff
            if firstOctet == 10 { return true }
            if firstOctet == 172 && ((value >> 16) & 0xff) >= 16 && ((value >> 16) & 0xff) <= 31 { return true }
            if firstOctet == 192 && ((value >> 16) & 0xff) == 168 { return true }
            return false
        case .v6(let groups):
            // fc00::/7 — top 7 bits are 1111110, i.e. first group's
            // high byte is 0xFC or 0xFD.
            guard let first = groups.first else { return false }
            let high = (first >> 8) & 0xff
            return high == 0xfc || high == 0xfd
        }
    }

    /// 169.254/16 (IPv4) or fe80::/10 (IPv6).
    var isLinkLocal: Bool {
        switch self {
        case .v4(let value):
            return (value >> 24) == 169 && ((value >> 16) & 0xff) == 254
        case .v6(let groups):
            guard let first = groups.first else { return false }
            // fe80::/10 — top 10 bits are 1111111010, i.e. first
            // group is 0xfe80…0xfebf.
            return first >= 0xfe80 && first <= 0xfebf
        }
    }

    /// IPv6 unique-local (fc00::/7). Exposed as a separate accessor
    /// for callers that want it distinct from `isPrivate`; the
    /// default `NetworkScope` derivation rolls it in.
    var isUniqueLocal: Bool {
        if case .v6 = self { return isPrivate } else { return false }
    }

    // MARK: - Parsing

    private static func parseV4(_ string: String) -> UInt32? {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var acc: UInt32 = 0
        for part in parts {
            guard let octet = UInt8(part) else { return nil }
            acc = (acc << 8) | UInt32(octet)
        }
        return acc
    }

    private static func parseV6(_ string: String) -> [UInt16]? {
        guard string.contains(":") else { return nil }
        // Split on "::" — at most one allowed.
        let halves = string.components(separatedBy: "::")
        guard halves.count <= 2 else { return nil }

        if halves.count == 2 {
            let left = halves[0].isEmpty ? [] : halves[0].split(separator: ":")
            let right = halves[1].isEmpty ? [] : halves[1].split(separator: ":")
            let leftGroups = left.compactMap { UInt16($0, radix: 16) }
            let rightGroups = right.compactMap { UInt16($0, radix: 16) }
            guard leftGroups.count == left.count, rightGroups.count == right.count else { return nil }
            let fill = 8 - leftGroups.count - rightGroups.count
            guard fill >= 0 else { return nil }
            return leftGroups + Array(repeating: 0, count: fill) + rightGroups
        }

        // No "::" — must be exactly 8 groups.
        let parts = string.split(separator: ":")
        guard parts.count == 8 else { return nil }
        let groups = parts.compactMap { UInt16($0, radix: 16) }
        guard groups.count == 8 else { return nil }
        return groups
    }
}
