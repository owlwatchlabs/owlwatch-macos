import ArgumentParser
import Foundation
import OWCodeSigning

struct VerifyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "verify",
        abstract: "Inspect a binary or bundle's code signature.",
        discussion: """
            Reads the code signature at <path> via the Security framework \
            and prints signature presence, structural validity, signing \
            identity, Team ID, signing identifier, CDHash, certificate \
            chain, and SecCodeSignatureFlags. Unsigned inputs print a \
            single 'Signature: none' line rather than erroring.

            Examples:
              owlwatch verify /bin/ls
              owlwatch verify /Applications/Safari.app
              owlwatch verify ~/Downloads/SomeApp.app/Contents/MacOS/SomeApp
            """
    )

    @Argument(help: "Path to a Mach-O binary or signed bundle.")
    var path: String

    func run() throws {
        let url = URL(fileURLWithPath: path)
        let sig = try OWCodeSigning.inspect(at: url)

        var lines: [String] = []
        lines.append("File:       \(url.path)")
        if let format = sig.format {
            lines.append("Format:     \(format)")
        }
        if !sig.isSigned {
            lines.append("Signature:  none")
            lines.append("Type:       \(sig.signatureType.rawValue)")
            print(lines.joined(separator: "\n"))
            return
        }

        lines.append("Signature:  embedded")
        lines.append("Validity:   \(sig.isValid ? "valid (structural)" : "invalid")")
        lines.append("Type:       \(formatSignatureType(sig.signatureType))")
        lines.append("Identifier: \(sig.identifier ?? "(none)")")
        lines.append("TeamID:     \(sig.teamIdentifier ?? "(none)")")
        lines.append("CDHash:     \(sig.cdHashHex ?? "(none)")")

        if sig.authorities.isEmpty {
            lines.append("Authority:  (none)")
        } else {
            for (index, name) in sig.authorities.enumerated() {
                let label = index == 0 ? "Authority:" : "          "
                lines.append("\(label)  \(name)")
            }
        }

        let flagText = sig.flags.symbolicForm
        lines.append("Flags:      \(flagText.isEmpty ? "(none)" : flagText)")

        if let runtimeVersion = sig.hardenedRuntimeVersion {
            lines.append("Runtime:    hardened, v\(runtimeVersion)")
        } else if sig.hasHardenedRuntime {
            lines.append("Runtime:    hardened (version unreported)")
        }

        lines.append("Notarized:  \(sig.isStapledForNotarization ? "stapled" : "no embedded ticket")")

        if let designatedRequirement = sig.designatedRequirement {
            lines.append("DR:         \(designatedRequirement)")
        }

        if let entitlements = sig.entitlements {
            if entitlements.isEmpty {
                lines.append("Entitlements: (blob present, no entries)")
            } else {
                lines.append("Entitlements (\(entitlements.count)):")
                for (key, value) in entitlements.sorted(by: { $0.key < $1.key }) {
                    lines.append("  \(key) = \(render(value))")
                }
            }
        }

        print(lines.joined(separator: "\n"))
    }

    private func render(_ entitlement: Entitlement) -> String {
        switch entitlement {
        case .bool(let value): return value ? "true" : "false"
        case .integer(let value): return String(value)
        case .string(let value): return "\"\(value)\""
        case .data(let value): return "<\(value.count) bytes>"
        case .array(let values):
            return "[" + values.map { render($0) }.joined(separator: ", ") + "]"
        case .dictionary(let pairs):
            let body = pairs
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\(render($0.value))" }
                .joined(separator: ", ")
            return "{" + body + "}"
        }
    }

    private func formatSignatureType(_ type: SignatureType) -> String {
        switch type {
        case .unsigned: return "unsigned"
        case .adhoc: return "adhoc"
        case .developerID: return "developer-id"
        case .appleDeveloper: return "apple-developer"
        case .appStore: return "app-store"
        case .apple: return "apple (first-party)"
        case .unknown: return "unknown"
        }
    }
}
