import ArgumentParser

// Root is `AsyncParsableCommand` so async subcommands (`LogsCommand`'s
// `--follow` mode) can dispatch into an async `run()`. Sync subcommands
// continue to work — `ParsableCommand` and `AsyncParsableCommand` are
// mix-and-match under one root.
@main
struct Owlwatch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "owlwatch",
        abstract: "Owlwatch command-line interface.",
        discussion: """
            Inspect and interact with Owlwatch's endpoint security surfaces.
            See https://github.com/owlwatchlabs/owlwatch-macos for the full surface.
            """,
        version: "0.6.0-m5",
        subcommands: [
            PSCommand.self,
            InspectCommand.self,
            VerifyCommand.self,
            NetstatCommand.self,
            PersistenceCommand.self,
            LoginItemsCommand.self,
            SystemExtensionsCommand.self,
            KernelExtensionsCommand.self,
            LoginHooksCommand.self,
            LogsCommand.self,
            TccEventsCommand.self
        ]
    )
}
