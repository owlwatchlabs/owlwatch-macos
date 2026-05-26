import OWBinary
import SwiftUI

/// Collapsible Mach-O facts inside the M18.5 dossier.
///
/// Default is collapsed: parsing 500MB Xcode is wasted work when the
/// user clicked into a row to read the rule findings. On expand, the
/// parse runs once off-main and the result is rendered inline.
///
/// This view stays self-contained — no view-model — because the
/// parse happens at most once per selected process and the dossier
/// recreates the view fresh on selection change.
struct MachOExpander: View {
    let path: String?

    @State private var expanded = false
    @State private var state: LoadState = .idle

    enum LoadState {
        case idle
        case loading
        case loaded(BinaryFile)
        case failed(String)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            content
                .padding(.top, 8)
        } label: {
            HStack(spacing: 6) {
                Text("Mach-O")
                    .font(.caption2.bold())
                    .foregroundStyle(Color.owlTextMuted)
                if case .loaded(let binary) = state {
                    Text("\(binary.slices.count) slice\(binary.slices.count == 1 ? "" : "s")")
                        .font(.owlMono(11))
                        .foregroundStyle(Color.owlTextDim)
                }
                Spacer()
            }
        }
        .tint(.owlTextMuted)
        .onChange(of: expanded) { _, isExpanded in
            if isExpanded, case .idle = state { load() }
        }
        .onChange(of: path) { _, _ in
            expanded = false
            state = .idle
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            Text("(tap to load)")
                .font(.owlMono(12))
                .foregroundStyle(Color.owlTextDim)
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Parsing…")
                    .font(.owlMono(12))
                    .foregroundStyle(Color.owlTextDim)
            }
        case .failed(let message):
            Text(message)
                .font(.owlMono(12))
                .foregroundStyle(Color.owlRed)
        case .loaded(let binary):
            MachOFacts(binary: binary)
        }
    }

    private func load() {
        guard let path else {
            state = .failed("No path for this process.")
            return
        }
        state = .loading
        Task.detached(priority: .userInitiated) {
            let url = URL(fileURLWithPath: path)
            let result: LoadState
            do {
                let binary = try OWBinary.parse(at: url, includeSymbols: false)
                result = .loaded(binary)
            } catch {
                result = .failed("Parse failed: \(error)")
            }
            await MainActor.run { state = result }
        }
    }
}

// MARK: - Facts

/// Compact summary of a parsed Mach-O: per-slice arch + filetype +
/// dylib count, plus the union of linked dylibs (capped). The full
/// segment table is the Inspector section's job — this expander
/// stays tight.
private struct MachOFacts: View {
    let binary: BinaryFile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(binary.slices.enumerated()), id: \.offset) { _, slice in
                SliceRow(slice: slice)
            }
            let dylibs = binary.linkedDylibs
            if !dylibs.isEmpty {
                DylibList(dylibs: dylibs)
            }
        }
    }
}

private struct SliceRow: View {
    let slice: Slice

    var body: some View {
        HStack(spacing: 8) {
            Text(slice.architecture.name)
                .font(.owlMono(11).bold())
                .foregroundStyle(Color.owlText)
            Text(slice.fileType.name)
                .font(.owlMono(11))
                .foregroundStyle(Color.owlTextMuted)
            Spacer()
            Text("\(slice.loadCommands.count) cmds")
                .font(.owlMono(11))
                .foregroundStyle(Color.owlTextDim)
        }
    }
}

private struct DylibList: View {
    let dylibs: [LoadCommand.Dylib]
    private let maxShown = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Linked dylibs (\(dylibs.count))")
                .font(.caption2.bold())
                .foregroundStyle(Color.owlTextMuted)
            ForEach(dylibs.prefix(maxShown), id: \.name) { dylib in
                Text(dylib.name)
                    .font(.owlMono(11))
                    .foregroundStyle(Color.owlTextMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if dylibs.count > maxShown {
                Text("+ \(dylibs.count - maxShown) more")
                    .font(.owlMono(11))
                    .foregroundStyle(Color.owlTextDim)
            }
        }
    }
}

