import ArgumentParser
import Foundation
import OWBinary

struct InspectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Parse a Mach-O or Universal binary and print its structural summary.",
        discussion: """
            Reads the file at <path>, parses its Mach-O / Universal headers \
            and load commands, and prints the architectures it contains, the \
            file type per slice, and (when --libs is set) every linked dylib.

            Examples:
              owlwatch inspect /bin/ls
              owlwatch inspect /usr/lib/dyld --libs
              owlwatch inspect ~/Applications/MyApp.app/Contents/MacOS/MyApp --libs --rpaths
            """
    )

    @Argument(help: "Path to the Mach-O or Universal binary to inspect.")
    var path: String

    @Flag(name: .shortAndLong, help: "List every linked dynamic library (LC_LOAD_DYLIB family).")
    var libs: Bool = false

    @Flag(name: .shortAndLong, help: "List every runtime search path (LC_RPATH).")
    var rpaths: Bool = false

    @Flag(name: .long, help: "Print the UUID and entry point per slice (LC_UUID + LC_MAIN).")
    var identity: Bool = false

    func run() throws {
        let url = URL(fileURLWithPath: path)
        let binary = try OWBinary.parse(at: url)

        var lines: [String] = []
        lines.append("File:   \(url.path)")
        lines.append("Format: \(binary.isUniversal ? "Universal (\(binary.slices.count) slices)" : "Mach-O (thin)")")

        for (index, slice) in binary.slices.enumerated() {
            lines.append("")
            let header = binary.isUniversal
                ? "Slice \(index): \(slice.architecture.name)"
                : "Architecture: \(slice.architecture.name)"
            lines.append(header)
            lines.append("  Type:  \(slice.fileType.name)")
            lines.append("  Flags: 0x\(String(slice.flags, radix: 16))")
            lines.append("  Load commands: \(slice.loadCommands.count)")

            if identity {
                appendIdentityLines(for: slice, into: &lines)
            }
            if rpaths {
                appendRPaths(for: slice, into: &lines)
            }
            if libs {
                appendDylibs(for: slice, into: &lines)
            }
        }

        FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
    }
}

private func appendIdentityLines(for slice: Slice, into lines: inout [String]) {
    for command in slice.loadCommands {
        switch command {
        case .uuid(let uuid):
            lines.append("  UUID:  \(uuid.uuidString)")
        case .main(let entryOffset, let stackSize):
            let entryHex = String(format: "0x%llx", entryOffset)
            lines.append("  Entry: \(entryHex) (stack size: \(stackSize))")
        default:
            break
        }
    }
}

private func appendRPaths(for slice: Slice, into lines: inout [String]) {
    let entries = slice.loadCommands.compactMap { command -> String? in
        if case let .rpath(path) = command { return path } else { return nil }
    }
    guard !entries.isEmpty else { return }
    lines.append("  RPATHs (\(entries.count)):")
    for entry in entries {
        lines.append("    \(entry)")
    }
}

private func appendDylibs(for slice: Slice, into lines: inout [String]) {
    let dylibs = slice.loadCommands.compactMap { command -> LoadCommand.Dylib? in
        if case let .dylib(payload) = command { return payload } else { return nil }
    }
    guard !dylibs.isEmpty else { return }
    lines.append("  Linked dylibs (\(dylibs.count)):")
    for dylib in dylibs {
        let kind: String
        if dylib.isSelfIdentity {
            kind = "self"
        } else if dylib.isWeak {
            kind = "weak"
        } else {
            kind = "required"
        }
        lines.append("    [\(kind)] \(dylib.name)")
    }
}
