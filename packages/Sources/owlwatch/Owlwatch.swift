import ArgumentParser

@main
struct Owlwatch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "owlwatch",
        abstract: "Owlwatch command-line interface.",
        discussion: """
            Inspect and interact with Owlwatch's endpoint security surfaces.
            See https://github.com/xorxorjmp/owlwatch for the full surface.
            """,
        version: "0.1.0-m0",
        subcommands: [PSCommand.self]
    )
}
