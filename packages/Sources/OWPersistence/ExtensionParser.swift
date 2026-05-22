import Foundation

// MARK: - System extension db.plist parser

/// Parse `/Library/SystemExtensions/db.plist`. The on-disk schema:
///
///     <dict>
///         <key>extensions</key>
///         <array>
///             <dict>
///                 <key>identifier</key>           <string>...</string>
///                 <key>teamID</key>               <string>...</string>
///                 <key>bundlePath</key>           <string>...</string>
///                 <key>state</key>                <string>activated_enabled</string>
///                 <key>uniqueID</key>             <string>...</string>
///                 <key>bundleVersion</key>
///                 <dict>
///                     <key>CFBundleShortVersionString</key> <string>...</string>
///                     <key>CFBundleVersion</key>            <string>...</string>
///                 </dict>
///                 <key>categories</key>
///                 <array>
///                     <string>com.apple.system_extension.network_extension</string>
///                 </array>
///             </dict>
///         </array>
///         <key>extensionPolicies</key>            <!-- ignored -->
///     </dict>
///
/// File absent → empty array (no system extensions ever activated).
/// Malformed plist → empty array (better than throwing — same posture
/// as `OWBinary`'s "tolerant on bad bundles").
internal func parseSystemExtensionDB(at plistPath: String) -> [SystemExtension] {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: plistPath)) else {
        return []
    }
    guard let root = try? PropertyListSerialization.propertyList(
        from: data, options: [], format: nil
    ) as? [String: Any] else {
        return []
    }
    guard let entries = root["extensions"] as? [[String: Any]] else {
        return []
    }
    return entries.compactMap(parseSystemExtensionEntry)
}

internal func parseSystemExtensionEntry(_ entry: [String: Any]) -> SystemExtension? {
    // The minimum a real entry has is `identifier` and `bundlePath`.
    guard let bundleIdentifier = entry["identifier"] as? String,
          let bundlePath = entry["bundlePath"] as? String else {
        return nil
    }
    let teamIdentifier = entry["teamID"] as? String
    let uniqueID = entry["uniqueID"] as? String

    let versionDict = entry["bundleVersion"] as? [String: Any]
    let shortVersion = versionDict?["CFBundleShortVersionString"] as? String
    let bundleVersion = versionDict?["CFBundleVersion"] as? String

    let categoryStrings = (entry["categories"] as? [String]) ?? []
    let categories = categoryStrings.map(SystemExtensionCategory.from(rawValue:))

    let stateString = entry["state"] as? String ?? ""
    let state = SystemExtensionState.from(rawValue: stateString)

    return SystemExtension(
        bundleIdentifier: bundleIdentifier,
        teamIdentifier: teamIdentifier,
        shortVersion: shortVersion,
        bundleVersion: bundleVersion,
        bundlePath: bundlePath,
        uniqueID: uniqueID,
        categories: categories,
        state: state
    )
}

// MARK: - Kext bundle walker

internal func enumerateKextBundles(in directory: String) -> [String] {
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
        return []
    }
    return entries
        .filter { $0.hasSuffix(".kext") && !$0.hasPrefix(".") }
        .map { (directory as NSString).appendingPathComponent($0) }
        .sorted()
}

internal func parseKernelExtension(at bundlePath: String, scope: KernelExtensionScope) -> KernelExtension? {
    let infoPath = (bundlePath as NSString).appendingPathComponent("Contents/Info.plist")
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: infoPath)) else {
        return nil
    }
    guard let info = try? PropertyListSerialization.propertyList(
        from: data, options: [], format: nil
    ) as? [String: Any] else {
        return nil
    }

    let bundleIdentifier = info["CFBundleIdentifier"] as? String
    let shortVersion = info["CFBundleShortVersionString"] as? String
    let bundleVersion = info["CFBundleVersion"] as? String
    let executableName = info["CFBundleExecutable"] as? String
    let executablePath = executableName.map { name in
        (bundlePath as NSString).appendingPathComponent("Contents/MacOS/\(name)")
    }
    return KernelExtension(
        bundlePath: bundlePath,
        bundleIdentifier: bundleIdentifier,
        shortVersion: shortVersion,
        bundleVersion: bundleVersion,
        executableName: executableName,
        executablePath: executablePath,
        scope: scope
    )
}
