import AppKit
import OWBinary
import OWCodeSigning
import SwiftUI
import UniformTypeIdentifiers

/// The M17 Inspector section. Surfaces M2's `OWBinary` parser and
/// M3's `OWCodeSigning` over a user-chosen Mach-O binary or bundle.
///
/// SectionHeader with SubnavPicker over `BinaryInspectorSection`
/// (Overview / Load Commands / Segments / Symbols / Signature /
/// Entitlements) + Open and Reload controls; below it the
/// path/header bar and the current-section content. Drag-drop a
/// file URL onto the content to load.
struct InspectorView: View {
    @State private var viewModel = BinaryInspectorViewModel()
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Inspector") {
                SubnavPicker(
                    selection: $viewModel.selectedSection,
                    options: BinaryInspectorSection.allCases.map { ($0, $0.displayName) }
                )
                Spacer()
                openReloadGroup
            }
            BinaryInspectorHeaderBar(viewModel: viewModel)
            Divider()
            BinaryInspectorContent(viewModel: viewModel)
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in await viewModel.load(url: url) }
                    }
                    return true
                }
        }
        .onAppear { applyFocus() }
        .onChange(of: model.focus) { _, _ in applyFocus() }
    }

    /// Cross-link target: load the supplied binary URL. Set from
    /// the Processes detail panel.
    ///
    /// Called from `.onAppear` and `.onChange(of: model.focus)`
    /// (both view-update phases), so mutations run on the next
    /// runloop to avoid the SwiftUI "Publishing changes from within
    /// view updates" fault.
    private func applyFocus() {
        guard case .binary(let url)? = model.focus else { return }
        Task { @MainActor in
            await viewModel.load(url: url)
            model.focus = nil
        }
    }

    @ViewBuilder
    private var openReloadGroup: some View {
        Button {
            chooseFile()
        } label: {
            Image(systemName: "doc.badge.plus")
                .foregroundStyle(Color.owlTextMuted)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("o", modifiers: .command)

        Button {
            Task { await viewModel.reload() }
        } label: {
            if viewModel.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(Color.owlTextMuted)
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.path == nil || viewModel.isLoading)
        .keyboardShortcut("r", modifiers: .command)
    }

    /// Driven by the toolbar Open button. The view model can also be
    /// pre-seeded by a drag-drop on the content area.
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true   // .app bundles
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Mach-O binary or signed bundle to inspect."
        if panel.runModal() == .OK, let url = panel.url {
            Task { await viewModel.load(url: url) }
        }
    }
}

// MARK: - Header bar

private struct BinaryInspectorHeaderBar: View {
    @Bindable var viewModel: BinaryInspectorViewModel

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.path?.lastPathComponent ?? "No binary selected")
                        .font(.headline)
                    if let path = viewModel.path {
                        Text(path.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    } else {
                        Text("Drop a file here or use ⌘O")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if viewModel.hasMultipleSlices,
                   let slices = viewModel.binary?.slices {
                    Picker("Slice", selection: $viewModel.selectedSliceIndex) {
                        ForEach(0..<slices.count, id: \.self) { index in
                            Text(slices[index].architecture.name).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .labelsHidden()
                }
            }
            if let error = viewModel.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Content router

private struct BinaryInspectorContent: View {
    @Bindable var viewModel: BinaryInspectorViewModel

    var body: some View {
        if viewModel.binary == nil && viewModel.path == nil {
            EmptyState(
                text: "Use ⌘O to open a Mach-O binary or signed bundle.",
                symbol: "doc.text.magnifyingglass"
            )
        } else {
            switch viewModel.selectedSection {
            case .overview:
                OverviewPane(viewModel: viewModel)
            case .loadCommands:
                LoadCommandsPane(viewModel: viewModel)
            case .segments:
                SegmentsPane(viewModel: viewModel)
            case .symbols:
                SymbolsPane(viewModel: viewModel)
            case .signature:
                SignaturePane(viewModel: viewModel)
            case .entitlements:
                EntitlementsPane(viewModel: viewModel)
            }
        }
    }
}

// MARK: - Overview

private struct OverviewPane: View {
    @Bindable var viewModel: BinaryInspectorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let binary = viewModel.binary {
                    let format = binary.isUniversal
                        ? "Universal (\(binary.slices.count) slices)"
                        : "Mach-O (thin)"
                    let architectures = binary.slices.map { $0.architecture.name }.joined(separator: ", ")
                    let entropyValue = viewModel.highEntropySectionCount > 0
                        ? "\(viewModel.highEntropySectionCount) (entropy > 7.0)"
                        : "none"
                    GroupBox("Binary") {
                        DetailGrid(rows: [
                            ("Format", format),
                            ("Architectures", architectures),
                            ("Linked dylibs", "\(binary.linkedDylibs.count)"),
                            ("High-entropy sections", entropyValue)
                        ])
                    }
                }
                if let slice = viewModel.currentSlice {
                    let sliceTitle = viewModel.hasMultipleSlices
                        ? "Slice \(viewModel.selectedSliceIndex): \(slice.architecture.name)"
                        : "Architecture: \(slice.architecture.name)"
                    GroupBox(sliceTitle) {
                        DetailGrid(rows: [
                            ("File type", slice.fileType.name),
                            ("Flags", String(format: "0x%x", slice.flags)),
                            ("Load commands", "\(slice.loadCommands.count)"),
                            ("UUID", uuidString(slice: slice) ?? "(none)"),
                            ("Entry offset", entryOffsetString(slice: slice) ?? "(no LC_MAIN)")
                        ])
                    }
                }
                if let signature = viewModel.signature {
                    GroupBox("Signature") {
                        DetailGrid(rows: [
                            ("Signed", signature.isSigned ? "yes" : "no"),
                            ("Validity", signature.isSigned
                                ? (signature.isValid ? "valid (structural)" : "invalid")
                                : "n/a"),
                            ("Type", signature.signatureType.rawValue),
                            ("Team ID", signature.teamIdentifier ?? "(none)"),
                            ("Identifier", signature.identifier ?? "(none)"),
                            ("Notarization", signature.isStapledForNotarization
                                ? "stapled"
                                : (signature.isSigned ? "no embedded ticket" : "n/a"))
                        ])
                    }
                }
            }
            .padding(16)
        }
    }

    private func uuidString(slice: Slice) -> String? {
        for command in slice.loadCommands {
            if case let .uuid(uuid) = command { return uuid.uuidString }
        }
        return nil
    }

    private func entryOffsetString(slice: Slice) -> String? {
        for command in slice.loadCommands {
            if case let .main(entry, stack) = command {
                return String(format: "0x%llx (stack %llu)", entry, stack)
            }
        }
        return nil
    }
}

// MARK: - Load commands

private struct LoadCommandsPane: View {
    @Bindable var viewModel: BinaryInspectorViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Filter by install name", text: $viewModel.filterText)
                    .textFieldStyle(.roundedBorder)
                Spacer()
                Text("\(viewModel.filteredDylibs.count) of \(viewModel.dylibsForCurrentSlice.count) dylibs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()
            DylibColumnHeader()
            List {
                ForEach(Array(viewModel.filteredDylibs.enumerated()), id: \.offset) { _, dylib in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(linkKind(dylib))
                            .font(.caption.monospaced())
                            .foregroundStyle(linkKindColor(dylib))
                            .frame(width: 70, alignment: .leading)
                        Text(dylib.name)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(versionString(dylib.currentVersion))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                        Text(versionString(dylib.compatibilityVersion))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                    }
                }
            }
            if !viewModel.rpathsForCurrentSlice.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("RPATHs (\(viewModel.rpathsForCurrentSlice.count))")
                        .font(.headline)
                    ForEach(viewModel.rpathsForCurrentSlice, id: \.self) { rpath in
                        Text(rpath)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
    }

    private func linkKind(_ dylib: LoadCommand.Dylib) -> String {
        if dylib.isSelfIdentity { return "self" }
        if dylib.isWeak { return "weak" }
        return "required"
    }

    private func linkKindColor(_ dylib: LoadCommand.Dylib) -> Color {
        if dylib.isSelfIdentity { return .blue }
        if dylib.isWeak { return .orange }
        return .primary
    }

    private func versionString(_ raw: UInt32) -> String {
        // Mach-O dylib version is encoded as X.Y.Z = (raw >> 16).(raw >> 8 & 0xff).(raw & 0xff).
        let major = (raw >> 16) & 0xffff
        let minor = (raw >> 8) & 0xff
        let patch = raw & 0xff
        return "\(major).\(minor).\(patch)"
    }
}

// MARK: - Segments

private struct SegmentsPane: View {
    @Bindable var viewModel: BinaryInspectorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(viewModel.segmentsForCurrentSlice, id: \.name) { segment in
                    SegmentBlock(
                        segment: segment,
                        entropies: viewModel.entropies.filter {
                            $0.sliceIndex == viewModel.selectedSliceIndex
                                && $0.segmentName == segment.name
                        }
                    )
                }
            }
            .padding(14)
        }
    }
}

private struct SegmentBlock: View {
    let segment: Segment
    let entropies: [SectionEntropy]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(segment.name)
                    .font(.headline.monospaced())
                Text("\(segment.initialProtection.symbolicForm) / \(segment.maxProtection.symbolicForm)")
                    .font(.caption.monospaced())
                    .foregroundStyle(protectionColor)
                Spacer()
                Text("vm \(formatBytes(segment.vmSize))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            ForEach(segment.sections, id: \.name) { section in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(section.name)
                        .font(.caption.monospaced())
                        .frame(width: 200, alignment: .leading)
                    Text(formatBytes(section.size))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                    Text(String(format: "fileoff 0x%x", section.fileOffset))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let entropy = entropies.first(where: { $0.sectionName == section.name }) {
                        Text(String(format: "H=%.3f", entropy.entropy))
                            .font(.caption.monospaced())
                            .foregroundStyle(entropy.entropy > 7.0 ? .red : .secondary)
                    }
                }
                .padding(.leading, 12)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// Highlight `rwx` segments in red — see `SegmentProtection`'s
    /// docstring for the "writable + executable is a strong packing
    /// signal" caveat.
    private var protectionColor: Color {
        let initial = segment.initialProtection
        if initial.contains(.write) && initial.contains(.execute) {
            return .red
        }
        return .secondary
    }
}

// MARK: - Symbols

private struct SymbolsPane: View {
    @Bindable var viewModel: BinaryInspectorViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Filter by symbol name", text: $viewModel.filterText)
                    .textFieldStyle(.roundedBorder)
                Toggle("External only", isOn: $viewModel.symbolsExternalOnly)
                    .toggleStyle(.checkbox)
                Spacer()
                if let slice = viewModel.currentSlice, let all = slice.symbols {
                    Text("\(viewModel.filteredSymbols.count) of \(all.count) symbols")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Load symbols") {
                        Task { await viewModel.refreshSymbols() }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()
            if viewModel.currentSlice?.symbols == nil {
                EmptyState(
                    text: "Press Load symbols to parse the symbol table.",
                    symbol: "function"
                )
            } else {
                SymbolColumnHeader()
                List {
                    ForEach(Array(viewModel.filteredSymbols.enumerated()), id: \.offset) { _, symbol in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(String(symbol.nmCode))
                                .font(.caption.monospaced())
                                .foregroundStyle(symbol.isExternal ? Color.primary : .secondary)
                                .frame(width: 30, alignment: .leading)
                            if case .undefined = symbol.kind {
                                Text("(import)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 150, alignment: .leading)
                            } else {
                                Text(String(format: "%016llx", symbol.value))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 150, alignment: .leading)
                            }
                            Text(symbol.name.isEmpty ? "(unnamed)" : symbol.name)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Signature

private struct SignaturePane: View {
    @Bindable var viewModel: BinaryInspectorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let signature = viewModel.signature {
                    GroupBox("Identity") {
                        DetailGrid(rows: [
                            ("Signed", signature.isSigned ? "yes" : "no"),
                            ("Validity", signature.isSigned
                                ? (signature.isValid ? "valid (structural)" : "invalid")
                                : "n/a"),
                            ("Type", formatType(signature.signatureType)),
                            ("Identifier", signature.identifier ?? "(none)"),
                            ("Team ID", signature.teamIdentifier ?? "(none)"),
                            ("CDHash", signature.cdHashHex ?? "(none)"),
                            ("Format", signature.format ?? "(unreported)")
                        ])
                    }

                    GroupBox("Certificate chain") {
                        if signature.authorities.isEmpty {
                            Text("(no certificate chain)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(signature.authorities.enumerated()), id: \.offset) { index, name in
                                    let role: String = {
                                        if index == 0 { return "leaf" }
                                        if index == signature.authorities.count - 1 { return "root" }
                                        return "interm."
                                    }()
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(role)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                            .frame(width: 60, alignment: .leading)
                                        Text(name)
                                            .font(.caption.monospaced())
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    GroupBox("Flags") {
                        let symbolic = signature.flags.symbolicForm
                        Text(symbolic.isEmpty ? "(no flags set)" : symbolic)
                            .font(.callout.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Hardened runtime + notarization") {
                        DetailGrid(rows: [
                            ("Hardened runtime",
                             signature.hasHardenedRuntime
                                ? (signature.hardenedRuntimeVersion.map { "v\($0)" } ?? "yes")
                                : "no"),
                            ("Stapled ticket",
                             signature.isStapledForNotarization
                                ? "yes (\(signature.stapledNotarizationTicket?.count ?? 0) bytes)"
                                : "no")
                        ])
                    }

                    if let designatedRequirement = signature.designatedRequirement {
                        GroupBox("Designated requirement") {
                            Text(designatedRequirement)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else if viewModel.path != nil {
                    ProgressView("Loading signature…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                }
            }
            .padding(16)
        }
    }

    private func formatType(_ type: SignatureType) -> String {
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

// MARK: - Entitlements

private struct EntitlementsPane: View {
    @Bindable var viewModel: BinaryInspectorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let entitlements = viewModel.signature?.entitlements {
                    if entitlements.isEmpty {
                        EmptyState(
                            text: "Entitlements blob present but empty — structural placeholder.",
                            symbol: "key.horizontal"
                        )
                    } else {
                        ForEach(entitlements.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(key)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(render(value))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(valueColor(value))
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } else if viewModel.signature?.isSigned == false {
                    EmptyState(text: "Binary is unsigned — no entitlements.", symbol: "key.horizontal")
                } else {
                    EmptyState(
                        text: "No entitlements embedded — most Apple system binaries don't carry one.",
                        symbol: "key.horizontal"
                    )
                }
            }
            .padding(16)
        }
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

    private func valueColor(_ entitlement: Entitlement) -> Color {
        switch entitlement {
        case .bool(let value): return value ? .green : .secondary
        default: return .primary
        }
    }
}

// MARK: - Reusable

private struct DylibColumnHeader: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Kind")
                .frame(width: 70, alignment: .leading)
            Text("Install name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Current")
                .frame(width: 80, alignment: .trailing)
            Text("Compat")
                .frame(width: 80, alignment: .trailing)
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

private struct SymbolColumnHeader: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("nm")
                .frame(width: 30, alignment: .leading)
            Text("Address")
                .frame(width: 150, alignment: .leading)
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

private struct DetailGrid: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 160, alignment: .leading)
                    Text(row.1)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func formatBytes(_ bytes: UInt64) -> String {
    if bytes < 1024 { return "\(bytes) B" }
    if bytes < 1024 * 1024 { return String(format: "%.1f KiB", Double(bytes) / 1024.0) }
    if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MiB", Double(bytes) / (1024.0 * 1024.0)) }
    return String(format: "%.1f GiB", Double(bytes) / (1024.0 * 1024.0 * 1024.0))
}
