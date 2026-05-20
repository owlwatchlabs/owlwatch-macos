import ArgumentParser

@main
struct NWCtl: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "nwctl",
        abstract: "Nightwatch command-line interface.",
        discussion: """
            Inspect and interact with Nightwatch's endpoint security surfaces.
            See https://github.com/xorxorjmp/nightwatch for the full surface.
            """,
        version: "0.1.0-m0",
        subcommands: [PSCommand.self]
    )
}
