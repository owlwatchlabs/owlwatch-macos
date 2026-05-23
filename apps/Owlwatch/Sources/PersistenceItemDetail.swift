import AppKit
import OWPersistence
import SwiftUI

/// Right column. Renders the full field surface of the selected item,
/// kind-specific. Tapping the path field reveals the file in Finder.
struct PersistenceItemDetail: View {
    let item: PersistenceItem?

    var body: some View {
        if let item {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.displayTitle)
                        .font(.title2)
                        .bold()
                    Divider()
                    body(for: item)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView(
                "Select an item",
                systemImage: "list.bullet.indent",
                description: Text("Pick a persistence item on the left to see its details.")
            )
        }
    }

    @ViewBuilder
    private func body(for item: PersistenceItem) -> some View {
        switch item {
        case .launchService(let service): LaunchServiceDetail(service: service)
        case .loginItem(let entry): LoginItemDetail(entry: entry)
        case .systemExtension(let ext): SystemExtensionDetail(ext: ext)
        case .kernelExtension(let ext): KernelExtensionDetail(ext: ext)
        case .loginHook(let hook): LoginHookDetail(hook: hook)
        case .liveMutation(let event): LiveMutationDetail(event: event)
        }
    }
}

// MARK: - Per-kind detail views

private struct LaunchServiceDetail: View {
    let service: LaunchService
    var body: some View {
        DetailField("Label", service.label ?? "—")
        DetailField("Scope", service.scope.rawValue)
        DetailPath("Plist", service.plistPath)
        DetailPath("Program", service.executablePath ?? "—")
        if !service.arguments.isEmpty {
            DetailField("Arguments", service.arguments.joined(separator: " "))
        }
        DetailField("State", service.isDisabled ? "disabled" : "enabled")
        DetailField("Triggers", triggers)
    }
    private var triggers: String {
        var parts: [String] = []
        if service.runAtLoad { parts.append("run-at-load") }
        if service.keepAlive.isActive { parts.append("keep-alive") }
        if !service.watchPaths.isEmpty { parts.append("watch-paths(\(service.watchPaths.count))") }
        if service.startInterval != nil { parts.append("interval") }
        if !service.startCalendarInterval.isEmpty { parts.append("calendar(\(service.startCalendarInterval.count))") }
        return parts.isEmpty ? "—" : parts.joined(separator: ", ")
    }
}

private struct LoginItemDetail: View {
    let entry: LoginItem
    var body: some View {
        DetailField("UUID", entry.uuid)
        DetailField("User ID", String(entry.userId))
        DetailField("Kind", String(describing: entry.kind))
        DetailField("Bundle Identifier", entry.bundleIdentifier ?? "—")
        DetailField("Team Identifier", entry.teamIdentifier ?? "—")
        DetailField("Developer", entry.developerName ?? "—")
        DetailField("Parent Identifier", entry.parentIdentifier ?? "—")
        DetailField("Disposition", entry.disposition.symbolicForm)
        DetailField("URL", entry.url ?? "—")
    }
}

private struct SystemExtensionDetail: View {
    let ext: SystemExtension
    var body: some View {
        DetailField("Bundle Identifier", ext.bundleIdentifier)
        DetailField("Team Identifier", ext.teamIdentifier ?? "—")
        DetailField("Version", ext.shortVersion ?? ext.bundleVersion ?? "—")
        DetailField("State", ext.state.rawValue)
        DetailField("Categories", ext.categories.map(\.rawValue).joined(separator: ", "))
        DetailField("Unique ID", ext.uniqueID ?? "—")
        DetailPath("Bundle Path", ext.bundlePath)
    }
}

private struct KernelExtensionDetail: View {
    let ext: KernelExtension
    var body: some View {
        DetailField("Bundle Identifier", ext.bundleIdentifier ?? "—")
        DetailField("Scope", ext.scope.rawValue)
        DetailField("Short Version", ext.shortVersion ?? "—")
        DetailField("Bundle Version", ext.bundleVersion ?? "—")
        DetailField("Executable", ext.executableName ?? "—")
        DetailPath("Bundle Path", ext.bundlePath)
        if let exe = ext.executablePath {
            DetailPath("Executable Path", exe)
        }
    }
}

private struct LoginHookDetail: View {
    let hook: LoginLogoutHook
    var body: some View {
        DetailField("Kind", hook.kind.rawValue)
        DetailField("Scope", hook.scope.rawValue)
        DetailPath("Script", hook.scriptPath)
        DetailPath("Plist", hook.plistPath)
    }
}

/// Live-event detail. Surfaces the raw FSEvents fields plus the
/// enriched payload (parsed `LaunchService` or `[LoginLogoutHook]`)
/// when one was attached. Removed-file events have no payload.
private struct LiveMutationDetail: View {
    let event: EnrichedMutation

    var body: some View {
        DetailField("Kind", event.mutation.kind.rawValue)
        DetailField("Scope", event.mutation.scope.rawValue)
        DetailField("Timestamp", event.mutation.timestamp.formatted(date: .abbreviated, time: .standard))
        DetailField("FSEvent ID", String(event.mutation.eventID))
        DetailPath("Path", event.mutation.path)

        if let service = event.launchService {
            Divider()
            Text("Parsed LaunchService")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            DetailField("Label", service.label ?? "—")
            DetailPath("Program", service.executablePath ?? "—")
            if !service.arguments.isEmpty {
                DetailField("Arguments", service.arguments.joined(separator: " "))
            }
            DetailField("State", service.isDisabled ? "disabled" : "enabled")
            DetailField("Run At Load", service.runAtLoad ? "true" : "false")
            DetailField("Keep Alive", service.keepAlive.isActive ? "true" : "false")
        } else if let hooks = event.hooks, !hooks.isEmpty {
            Divider()
            Text("Parsed Hooks")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            ForEach(hooks, id: \.self) { hook in
                DetailField("\(hook.kind.rawValue.capitalized) Hook", hook.scriptPath)
            }
        } else {
            Text(event.mutation.kind == .removed
                 ? "(file was removed — no content to parse)"
                 : "(no parseable payload for this scope)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }
}

// MARK: - Field primitives

/// One name/value row.
private struct DetailField: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospaced())
                .textSelection(.enabled)
        }
    }
}

/// A path-typed field with a "Show in Finder" affordance on hover.
private struct DetailPath: View {
    let label: String
    let path: String

    init(_ label: String, _ path: String) {
        self.label = label
        self.path = path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(path)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: path)]
                    )
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
        }
    }
}
