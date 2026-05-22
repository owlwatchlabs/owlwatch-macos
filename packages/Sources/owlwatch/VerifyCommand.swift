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

        print(lines.joined(separator: "\n"))
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
