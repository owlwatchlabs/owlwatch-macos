import ArgumentParser

@main
struct Owlwatch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "owlwatch",
        abstract: "Owlwatch command-line interface.",
        discussion: """
            Inspect and interact with Owlwatch's endpoint security surfaces.
            See https://github.com/owlwatchlabs/owlwatch-macos for the full surface.
            """,
        version: "0.3.0-m2",
        subcommands: [PSCommand.self, InspectCommand.self]
    )
}
