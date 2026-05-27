import OWBinary
import SwiftUI

/// Collapsible Mach-O facts inside the M18.5 dossier.
///
/// Default is collapsed: parsing 500 MB Xcode is wasted work when the
/// user clicked into a row to read the rule findings. On expand we
/// kick off a single off-main pass that parses the Mach-O headers
/// and computes Shannon entropy per section. Both results land
/// together, so the panel renders fully populated rather than
/// partially-filled.
///
/// The panel surface is intentionally dense — type/arch, segments
/// with permissions, entropy peaks, dylibs, UUID — because the full
/// segment / symbol / disassembly view lives in the standalone
/// Inspector section. The CTA at the bottom hops there.
struct MachOExpander: View {
    let path: String?
    let onOpenInInspector: () -> Void

    // Default-expanded: the Mach-O surface is the densest part of
    // the dossier and the user reaches the section to read it.
    // Collapsing is opt-out, not opt-in.
    @State private var expanded = true
    @State private var state: LoadState = .idle

    enum LoadState {
        case idle
        case loading
        case loaded(BinaryFile, [SectionEntropy])
        case failed(String)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            content
                .padding(.top, 8)
        } label: {
            label
        }
        .tint(.owlAmber)
        .padding(12)
        .background(Color.owlSurface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.owlBorder, lineWidth: 1)
        )
        // Kick off the initial load when the section first appears
        // expanded (the default). `.onChange(of: expanded)` doesn't
        // fire for the initial value.
        .task(id: path) {
            if expanded, case .idle = state { load() }
        }
        .onChange(of: expanded) { _, isExpanded in
            if isExpanded, case .idle = state { load() }
        }
        .onChange(of: path) { _, _ in
            // Reset to default-expanded on a new selection. State
            // is cleared so the `.task` re-runs against the new id.
            expanded = true
            state = .idle
        }
    }

    @ViewBuilder
    private var label: some View {
        HStack(spacing: 6) {
            Text("MACH-O & ENTITLEMENTS")
                .font(.owlMono(11).bold())
                .tracking(0.6)
                .foregroundStyle(Color.owlAmber)
            Spacer()
            if expanded {
                Text("expanded in place")
                    .font(.owlMono(10.5))
                    .foregroundStyle(Color.owlTextDim)
            }
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
        case .loaded(let binary, let entropies):
            MachOFacts(
                binary: binary,
                entropies: entropies,
                onOpenInInspector: onOpenInInspector
            )
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
                let entropies = (try? OWBinary.sectionEntropies(of: binary)) ?? []
                result = .loaded(binary, entropies)
            } catch {
                result = .failed("Parse failed: \(error)")
            }
            await MainActor.run { state = result }
        }
    }
}

// MARK: - Facts

/// Dense triage-oriented summary of a parsed Mach-O. Rows use the
/// dossier's KeyValueRow label column (120pt) so values align with
/// the Identity section above. Suspicious values (`rwx` segments,
/// high entropy) render in red.
private struct MachOFacts: View {
    let binary: BinaryFile
    let entropies: [SectionEntropy]
    let onOpenInInspector: () -> Void

    /// Read this binary as the "primary" slice — the first one.
    /// For Universal binaries the macOS dynamic loader picks the
    /// slice that matches the host arch; we don't reproduce that
    /// resolution here, but the load-command / segment / entropy
    /// surface is comparable across slices for triage purposes.
    private var primary: Slice? { binary.slices.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Type / arch", typeArch)
            row("Load commands", "\(primary?.loadCommands.count ?? 0)")
            segmentsBlock
            entropyBlock
            dylibsBlock
            if let uuidValue = uuid {
                row("UUID", formatUUID(uuidValue))
            }
            row("Entitlements", "(no signature)", muted: true)
            symbolsRow
            openInInspectorButton
        }
    }

    /// Symbols are never auto-loaded — parsing the symbol table
    /// can stretch into seconds on large binaries (Xcode, Chrome).
    /// The row carries a dim right-aligned affordance that hands
    /// off to the standalone Inspector where loading + browsing
    /// is the section's primary job.
    @ViewBuilder
    private var symbolsRow: some View {
        let count = primary?.symbols?.count
        HStack(alignment: .firstTextBaseline) {
            Text("Symbols")
                .foregroundStyle(Color.owlTextMuted)
                .frame(width: 110, alignment: .leading)
            if let count {
                Text("(\(grouped(count)))")
                    .foregroundStyle(Color.owlText)
            }
            Spacer()
            Button(action: onOpenInInspector) {
                Text(count == nil ? "load" : "expand")
                    .foregroundStyle(Color.owlTextDim)
            }
            .buttonStyle(.plain)
        }
        .font(.owlMono(12))
    }

    // MARK: - Row primitives

    /// Single-value row: label in the 110pt column, value to the right.
    @ViewBuilder
    private func row(_ key: String, _ value: String, muted: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .foregroundStyle(Color.owlTextMuted)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .foregroundStyle(muted ? Color.owlTextDim : Color.owlText)
                .textSelection(.enabled)
            Spacer()
        }
        .font(.owlMono(12))
    }

    /// Multi-value block: label in the 110pt column, vertically-
    /// stacked entries to the right. Used for segments / entropy /
    /// dylibs — horizontal middot-separated runs broke unreadably
    /// on the narrow detail pane (SwiftUI's `Text + Text`
    /// concatenation wraps at character boundaries and sliced
    /// `__TEXT` mid-name).
    @ViewBuilder
    private func block<Content: View>(
        _ key: String, @ViewBuilder rows: () -> Content
    ) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .foregroundStyle(Color.owlTextMuted)
                .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) { rows() }
            Spacer()
        }
        .font(.owlMono(12))
    }

    // MARK: - Blocks

    @ViewBuilder
    private var segmentsBlock: some View {
        let segs = primary?.segments ?? []
        if !segs.isEmpty {
            block("Segments") {
                ForEach(Array(segs.enumerated()), id: \.offset) { _, seg in
                    let perms = seg.initialProtection.symbolicForm
                    let suspicious = seg.initialProtection.contains([.write, .execute])
                    HStack(spacing: 6) {
                        // rwx is the alarming combination — name and
                        // permissions both flip to red so the eye
                        // reads them as a single hot row.
                        Text(seg.name)
                            .foregroundStyle(suspicious ? Color.owlRed : Color.owlText)
                        Text(perms)
                            .foregroundStyle(suspicious ? Color.owlRed : Color.owlTextMuted)
                        Spacer()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var entropyBlock: some View {
        let top = entropies
            .filter { $0.sliceIndex == 0 }
            .sorted { $0.entropy > $1.entropy }
            .prefix(3)
        if !top.isEmpty {
            block("Entropy") {
                ForEach(Array(top.enumerated()), id: \.offset) { _, entry in
                    let value = String(format: "%.2f", entry.entropy)
                    // ≥7.2 is the "near the 8.0 ceiling" amber band —
                    // packed/compressed sections in normal binaries
                    // rarely cross this line.
                    let hot = entry.entropy >= 7.2
                    HStack(spacing: 6) {
                        // The section + its value share the same
                        // emphasis color so the eye reads them as a
                        // single hot pair; "/ 8.0" stays dim as the
                        // reference scale.
                        Text(entry.sectionName)
                            .foregroundStyle(hot ? Color.owlAmber : Color.owlText)
                        Text(value)
                            .foregroundStyle(hot ? Color.owlAmber : Color.owlTextMuted)
                        Text("/ 8.0")
                            .foregroundStyle(Color.owlTextDim)
                        Spacer()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var dylibsBlock: some View {
        let dylibs = binary.linkedDylibs
        if !dylibs.isEmpty {
            block("Linked dylibs") {
                ForEach(dylibs.prefix(4), id: \.name) { dylib in
                    Text(shortDylibName(dylib.name))
                        .foregroundStyle(Color.owlText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if dylibs.count > 4 {
                    Text("+ \(dylibs.count - 4) more")
                        .foregroundStyle(Color.owlTextDim)
                }
            }
        }
    }

    /// `/usr/lib/libSystem.B.dylib` → `libSystem.B`. Drops the
    /// directory and the `.dylib` extension so the row stays inside
    /// the column width budget.
    private func shortDylibName(_ name: String) -> String {
        let leaf = (name as NSString).lastPathComponent
        if leaf.hasSuffix(".dylib") { return String(leaf.dropLast(6)) }
        return leaf
    }

    // MARK: - Derivations

    private var typeArch: String {
        guard let primary else { return "—" }
        let fileType = primary.fileType.name
        if binary.slices.count == 1 {
            return "\(fileType) · \(primary.architecture.name) (single)"
        }
        let archs = binary.slices.map(\.architecture.name).joined(separator: " + ")
        return "\(fileType) · \(archs) (universal)"
    }

    private var uuid: UUID? {
        for command in primary?.loadCommands ?? [] {
            if case let .uuid(value) = command { return value }
        }
        return nil
    }

    /// `CAFE1234-...-DEAD` style: keep the leading 8 hex digits and
    /// the trailing 4, drop the middle.
    private func formatUUID(_ value: UUID) -> String {
        let hex = value.uuidString.replacingOccurrences(of: "-", with: "")
        guard hex.count >= 12 else { return value.uuidString }
        let head = hex.prefix(8)
        let tail = hex.suffix(4)
        return "\(head)-…-\(tail)"
    }

    // MARK: - CTA

    @ViewBuilder
    private var openInInspectorButton: some View {
        Button(action: onOpenInInspector) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                Text("Open in standalone Inspector")
                    .font(.owlMono(12))
                Spacer()
            }
            .foregroundStyle(Color.owlAmber)
            .padding(.top, 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Adapter for Slice.segments

private extension Slice {
    /// All `LC_SEGMENT(_64)` payloads in load-command order. Filters
    /// out the special `__PAGEZERO` segment whose only purpose is to
    /// reserve virtual address space at zero — it has no permissions
    /// or contents, and rendering it as `---` is noise.
    var segments: [Segment] {
        loadCommands.compactMap {
            if case let .segment(seg) = $0, seg.name != "__PAGEZERO" {
                return seg
            }
            return nil
        }
    }
}
