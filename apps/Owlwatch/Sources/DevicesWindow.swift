import OWDevices
import SwiftUI

/// Top-level window for the M11.4 Devices viewer.
/// Three columns: sidebar (kinds + badges) | center list (devices or
/// live events) | trailing detail.
struct DevicesWindow: View {
    @State private var viewModel = DevicesViewModel()

    var body: some View {
        NavigationSplitView {
            DevicesSidebar(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } content: {
            DevicesCenterPane(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 320, ideal: 420)
        } detail: {
            DevicesDetailPane(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380)
        }
        .navigationTitle("Devices — Owlwatch")
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let last = viewModel.lastRefresh {
                    Text("Last refresh: \(last.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        .frame(minWidth: 880, minHeight: 480)
        .task {
            viewModel.startMonitor()
            if viewModel.lastRefresh == nil {
                viewModel.refresh()
            }
        }
        .onDisappear {
            viewModel.stopMonitor()
        }
    }
}

// MARK: - Sidebar

private struct DevicesSidebar: View {
    @Bindable var viewModel: DevicesViewModel

    var body: some View {
        List(DeviceSidebarKind.allCases, selection: $viewModel.selectedKind) { kind in
            NavigationLink(value: kind) {
                Label(kind.displayName, systemImage: kind.symbolName)
                    .badge(badge(for: kind))
            }
        }
        .navigationTitle("Devices")
    }

    private func badge(for kind: DeviceSidebarKind) -> Int {
        switch kind {
        case .cameras:
            return viewModel.cameras.count
        case .microphones:
            return viewModel.microphones.count
        case .events:
            // Show unseen count while on snapshot tabs; total while
            // on the Events tab itself.
            return viewModel.selectedKind == .events
                ? viewModel.events.count
                : viewModel.unseenEventCount
        }
    }
}

// MARK: - Center pane (per-kind list)

private struct DevicesCenterPane: View {
    @Bindable var viewModel: DevicesViewModel

    var body: some View {
        switch viewModel.selectedKind {
        case .cameras:
            DevicesList(items: viewModel.cameras.map { .camera($0) },
                        selection: $viewModel.selectedItemID,
                        emptyTitle: "No Cameras",
                        emptyBody: "No cameras attached to this Mac.")
        case .microphones:
            DevicesList(items: viewModel.microphones.map { .microphone($0) },
                        selection: $viewModel.selectedItemID,
                        emptyTitle: "No Microphones",
                        emptyBody: "No microphones attached to this Mac.")
        case .events:
            DevicesList(items: viewModel.events.enumerated().map { offset, change in
                            .event(change, offset: offset)
                        },
                        selection: $viewModel.selectedItemID,
                        emptyTitle: "No Events Yet",
                        emptyBody: "Mic and camera state changes will appear here as they happen.")
        }
    }
}

/// Item enum for the center list. Folds cameras, microphones, and
/// live events into one heterogeneous list type so the same SwiftUI
/// list code handles all three sidebar tabs.
enum DevicesItem: Identifiable, Hashable {
    case camera(Camera)
    case microphone(Microphone)
    case event(DeviceStateChange, offset: Int)

    var id: String {
        switch self {
        case .camera(let camera): return "c:\(camera.id)"
        case .microphone(let mic): return "m:\(mic.id)"
        case .event(let change, let offset):
            // The kind + UID + timestamp combination might collide if
            // two events fire within the same nanosecond (theoretically
            // possible on parallel listener queues). The offset (the
            // event's position in the newest-first array) breaks that
            // tie deterministically.
            return "e:\(change.kind.rawValue):\(change.id):"
                + "\(change.timestamp.timeIntervalSince1970):\(offset)"
        }
    }

    var primaryText: String {
        switch self {
        case .camera(let camera): return camera.name
        case .microphone(let mic): return mic.name
        case .event(let change, _):
            return "\(change.kind.rawValue) \(change.isInUse ? "→ ON" : "→ off")"
        }
    }

    var secondaryText: String {
        switch self {
        case .camera(let camera): return camera.manufacturer ?? camera.id
        case .microphone(let mic): return mic.manufacturer ?? mic.id
        case .event(let change, _): return change.name
        }
    }

    var stateBadge: String? {
        switch self {
        case .camera(let camera):
            return camera.isInUse ? "in use" : nil
        case .microphone(let mic):
            return mic.isInUse ? "in use" : nil
        case .event(let change, _):
            // Render timestamp as the badge for events.
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter.string(from: change.timestamp)
        }
    }
}

private struct DevicesList: View {
    let items: [DevicesItem]
    @Binding var selection: String?
    let emptyTitle: String
    let emptyBody: String

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView(
                emptyTitle, systemImage: "questionmark.dashed",
                description: Text(emptyBody)
            )
        } else {
            List(items, selection: $selection) { item in
                DevicesRow(item: item).tag(item.id)
            }
            .listStyle(.inset)
        }
    }
}

private struct DevicesRow: View {
    let item: DevicesItem

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.secondaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let badge = item.stateBadge {
                Text(badge)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeBackground(badge))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    private func badgeBackground(_ badge: String) -> Color {
        if badge == "in use" { return .red.opacity(0.22) }
        return .secondary.opacity(0.18)
    }
}

// MARK: - Detail pane

private struct DevicesDetailPane: View {
    @Bindable var viewModel: DevicesViewModel

    var body: some View {
        if let item = selectedItem {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    body(for: item)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView(
                "Select an item",
                systemImage: "list.bullet.indent",
                description: Text("Pick a device or event on the left to see its details.")
            )
        }
    }

    private var selectedItem: DevicesItem? {
        guard let id = viewModel.selectedItemID else { return nil }
        // Walk all three sources; the kind prefix on the id tells us
        // which to search.
        if id.hasPrefix("c:") {
            if let camera = viewModel.cameras.first(where: { "c:\($0.id)" == id }) {
                return .camera(camera)
            }
        } else if id.hasPrefix("m:") {
            if let mic = viewModel.microphones.first(where: { "m:\($0.id)" == id }) {
                return .microphone(mic)
            }
        } else if id.hasPrefix("e:") {
            for (offset, event) in viewModel.events.enumerated() {
                let candidate = DevicesItem.event(event, offset: offset)
                if candidate.id == id { return candidate }
            }
        }
        return nil
    }

    @ViewBuilder
    private func body(for item: DevicesItem) -> some View {
        switch item {
        case .camera(let camera): CameraDetail(camera: camera)
        case .microphone(let mic): MicrophoneDetail(mic: mic)
        case .event(let event, _): EventDetail(event: event)
        }
    }
}

private struct CameraDetail: View {
    let camera: Camera
    var body: some View {
        Text(camera.name).font(.title2).bold()
        Divider()
        DetailField("State", camera.isInUse ? "in use" : "idle")
        DetailField("Manufacturer", camera.manufacturer ?? "—")
        DetailField("Model ID", camera.modelID ?? "—")
        DetailField("External", camera.isExternal ? "yes" : "no")
        DetailField("Virtual", camera.isVirtual ? "yes" : "no")
        DetailField("Device UID", camera.id)
    }
}

private struct MicrophoneDetail: View {
    let mic: Microphone
    var body: some View {
        Text(mic.name).font(.title2).bold()
        Divider()
        DetailField("State", mic.isInUse ? "in use" : "idle")
        DetailField("Manufacturer", mic.manufacturer ?? "—")
        DetailField("External", mic.isExternal ? "yes" : "no")
        DetailField("Device UID", mic.id)
    }
}

private struct EventDetail: View {
    let event: DeviceStateChange
    @State private var candidates: [ProcessCandidate] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(event.kind.rawValue.capitalized) \(event.isInUse ? "turned ON" : "turned off")")
                .font(.title2).bold()
            Divider()
            DetailField("Device", event.name)
            DetailField("Device UID", event.id)
            DetailField("Timestamp", event.timestamp.formatted(date: .abbreviated, time: .standard))

            if event.isInUse {
                Divider()
                Text("Best-effort attribution")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                if candidates.isEmpty {
                    Text("(no signals matched — background daemon with existing TCC grant?)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(candidates.enumerated()), id: \.offset) { _, candidate in
                        AttributionRow(candidate: candidate)
                    }
                }
            }
        }
        .onAppear {
            if event.isInUse {
                candidates = OWDevices.attribute(event)
            }
        }
    }
}

private struct AttributionRow: View {
    let candidate: ProcessCandidate
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(candidate.confidence.rawValue.uppercased())
                    .font(.caption.bold().monospaced())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(confidenceBackground.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                Text(candidate.identifier ?? "(unknown)")
                    .font(.body.monospaced())
                if let pid = candidate.pid {
                    Text("pid=\(pid)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(candidate.evidence)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var confidenceBackground: Color {
        switch candidate.confidence {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .secondary
        }
    }
}

// MARK: - Field primitives (mirrors the Persistence window's helpers)

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
