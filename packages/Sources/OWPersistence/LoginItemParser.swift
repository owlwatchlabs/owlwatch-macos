import Darwin
import Foundation

/// Internal helpers for ``OWPersistence/OWPersistence/loginItems()``.
///
/// The Background Task Management (BTM) database lives in a system
/// directory not readable by ordinary users; Apple's `sfltool dumpbtm`
/// is the canonical user-mode reader. We shell to it and parse the
/// structured-text output here.
///
/// The output is NOT a contractually stable format — Apple has changed
/// it across macOS versions in minor ways. The parser is therefore
/// tolerant: unrecognized lines are skipped, items missing required
/// fields (UUID, Name) are dropped, the raw type text and value are
/// preserved so callers can match on the raw form even when our
/// classified enum doesn't recognize a new type.

extension OWPersistence {
    /// Invoke `/usr/bin/sfltool dumpbtm` and return its stdout. Empty
    /// string on any failure (tool missing, non-zero exit, decoding
    /// error). Callers treat empty parse output as "no login items
    /// visible" rather than as an error.
    static func runSfltoolDumpbtm() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sfltool")
        process.arguments = ["dumpbtm"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Parse `sfltool dumpbtm` output into ``LoginItem`` records.
///
/// Structure of the output:
///
///     ========================
///      Records for UID 501 : <uuid>
///     ========================
///
///      ServiceManagement migrated: true
///      LaunchServices registered: true
///
///      Items:
///
///      #1:
///                      UUID: <uuid>
///                      Name: <display name>
///            Developer Name: <name or (null)>
///           Team Identifier: <team id or (null)>
///                      Type: app (0x2)
///                     Flags: [ ... ] (0xN)
///               Disposition: [enabled, allowed, notified] (0xb)
///                Identifier: <btm internal id>
///                       URL: <file:// url or relative path>
///                Generation: N
///         Bundle Identifier: <bundle id>
///         Parent Identifier: <parent btm id, optional>
///
internal func parseSfltoolDumpbtm(_ output: String) -> [LoginItem] {
    var items: [LoginItem] = []
    var currentUserId: uid_t = 0
    var currentItemFields: [String: String] = [:]
    var inItemsSection = false

    let lines = output.components(separatedBy: "\n")
    for line in lines {
        // New user-section header — flush any pending item and reset.
        if let uid = extractUserId(line: line) {
            commitItem(fields: &currentItemFields, userId: currentUserId, into: &items)
            currentUserId = uid
            inItemsSection = false
            continue
        }
        // Start of items list within a section.
        if line.trimmingCharacters(in: .whitespaces) == "Items:" {
            inItemsSection = true
            continue
        }
        guard inItemsSection else { continue }
        // Start of a new item — commit the previous one.
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") && trimmed.hasSuffix(":") {
            commitItem(fields: &currentItemFields, userId: currentUserId, into: &items)
            continue
        }
        // Field line — split on the first colon (some values like URLs
        // also contain colons, so use range(of:) to limit to the first).
        if let separator = trimmed.range(of: ":") {
            let key = String(trimmed[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                currentItemFields[key] = value
            }
        }
    }
    // Final flush.
    commitItem(fields: &currentItemFields, userId: currentUserId, into: &items)
    return items
}

private func extractUserId(line: String) -> uid_t? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("Records for UID ") else { return nil }
    let suffix = trimmed.dropFirst("Records for UID ".count)
    // Format: "501 : <uuid>" — take the integer up to the colon.
    let parts = suffix.split(separator: ":", maxSplits: 1)
    guard let uidPart = parts.first else { return nil }
    let trimmedUid = String(uidPart).trimmingCharacters(in: .whitespaces)
    // Handle negative UIDs (UID -2 = "nobody") which become bit-pattern
    // 0xFFFFFFFE when bridged through uid_t.
    if let signed = Int32(trimmedUid) {
        return uid_t(bitPattern: signed)
    }
    return UInt32(trimmedUid).map { uid_t($0) }
}

private func commitItem(
    fields: inout [String: String],
    userId: uid_t,
    into items: inout [LoginItem]
) {
    defer { fields.removeAll() }
    if let item = buildLoginItem(fields: fields, userId: userId) {
        items.append(item)
    }
}

internal func buildLoginItem(fields: [String: String], userId: uid_t) -> LoginItem? {
    guard let uuid = fields["UUID"], let name = fields["Name"] else { return nil }
    let (typeName, typeRawValue) = parseTypeField(fields["Type"] ?? "")
    let dispositionBits = parseDispositionField(fields["Disposition"] ?? "")
    return LoginItem(
        uuid: uuid,
        userId: userId,
        name: name,
        developerName: nullableString(fields["Developer Name"]),
        teamIdentifier: nullableString(fields["Team Identifier"]),
        bundleIdentifier: nullableString(fields["Bundle Identifier"]),
        parentIdentifier: nullableString(fields["Parent Identifier"]),
        identifier: nullableString(fields["Identifier"]),
        url: nullableString(fields["URL"]),
        kind: LoginItemKind.from(rawName: typeName, rawValue: typeRawValue),
        kindRawValue: typeRawValue,
        disposition: LoginItemDisposition(rawValue: dispositionBits)
    )
}

/// Parse `"app (0x2)"` or `"legacy agent (0x10008)"` into (name, raw).
/// Returns `(value, 0)` if the format doesn't match.
internal func parseTypeField(_ value: String) -> (name: String, rawValue: Int) {
    guard let openParen = value.lastIndex(of: "(") else {
        return (value.trimmingCharacters(in: .whitespaces), 0)
    }
    let name = value[..<openParen].trimmingCharacters(in: .whitespaces)
    let inside = value[openParen...].dropFirst()  // drop "("
    guard let closeParen = inside.firstIndex(of: ")") else { return (name, 0) }
    let hexPart = inside[..<closeParen].trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "0x", with: "")
    let rawValue = Int(hexPart, radix: 16) ?? 0
    return (name, rawValue)
}

/// Parse `"[enabled, allowed, notified] (0xb)"` into the bitfield value.
/// Returns 0 if the format doesn't match.
internal func parseDispositionField(_ value: String) -> UInt32 {
    guard let openParen = value.lastIndex(of: "(") else { return 0 }
    let inside = value[openParen...].dropFirst()
    guard let closeParen = inside.firstIndex(of: ")") else { return 0 }
    let hexPart = inside[..<closeParen].trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "0x", with: "")
    return UInt32(hexPart, radix: 16) ?? 0
}

private func nullableString(_ value: String?) -> String? {
    guard let value, !value.isEmpty, value != "(null)" else { return nil }
    return value
}
