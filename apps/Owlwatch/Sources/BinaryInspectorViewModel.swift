import Foundation
import OWBinary
import OWCodeSigning

/// Drives the M16.5 Binary Inspector window. Holds a single parsed
/// binary + its code signature, plus the slice currently selected for
/// per-slice views (load commands, segments, symbols).
///
/// The window operates on one file at a time. The user picks via
/// `NSOpenPanel` (or, eventually, drag-drop); the view model parses
/// off-main and replaces its state atomically.
///
/// Symbol-table parsing is opt-in (`includeSymbols`) because large
/// binaries can carry hundreds of thousands of entries and the cost is
/// noticeable — users only pay it when they navigate to the Symbols
/// section.
@MainActor
@Observable
final class BinaryInspectorViewModel {
    // MARK: - Inputs

    /// The path currently inspected. `nil` when the window first opens
    /// or the user clears the selection.
    var path: URL?

    /// The active sidebar section.
    var selectedSection: BinaryInspectorSection = .overview {
        didSet {
            if selectedSection == .symbols && shouldFetchSymbols {
                Task { await self.refreshSymbols() }
            }
        }
    }

    /// Index of the currently-selected slice (only meaningful for
    /// Universal binaries with more than one slice).
    var selectedSliceIndex: Int = 0

    // MARK: - Outputs

    var binary: BinaryFile?
    var signature: CodeSignature?
    var entropies: [SectionEntropy] = []
    var lastError: String?
    var isLoading: Bool = false
    var lastRefresh: Date?

    /// Filter text applied to the Symbols and Load Commands lists.
    /// Empty = no filter.
    var filterText: String = ""

    /// Restrict the symbols list to external symbols only
    /// (imports + exports).
    var symbolsExternalOnly: Bool = false

    // MARK: - Computed

    /// The current slice if the index is valid; otherwise the first
    /// slice (or nil for an empty binary).
    var currentSlice: Slice? {
        guard let slices = binary?.slices, !slices.isEmpty else { return nil }
        let index = min(max(0, selectedSliceIndex), slices.count - 1)
        return slices[index]
    }

    var hasMultipleSlices: Bool {
        (binary?.slices.count ?? 0) > 1
    }

    /// True when the user has navigated to Symbols but the parsed
    /// binary didn't include the symbol table (the initial parse
    /// skips it for performance).
    private var shouldFetchSymbols: Bool {
        guard let binary else { return false }
        return binary.slices.contains { $0.symbols == nil }
    }

    // MARK: - Loading

    /// Parse a new binary at `url` and pull its code signature in
    /// parallel. Replaces existing state on success.
    func load(url: URL) async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let parsed = await Task.detached { () -> BinaryParseResult in
            do {
                let bin = try OWBinary.parse(at: url, includeSymbols: false)
                let entropies = (try? OWBinary.sectionEntropies(of: bin)) ?? []
                return BinaryParseResult(binary: bin, entropies: entropies, error: nil)
            } catch {
                return BinaryParseResult(binary: nil, entropies: [], error: "Binary parse failed: \(error)")
            }
        }.value

        let signed = await Task.detached { () -> SignatureInspectResult in
            do {
                return SignatureInspectResult(signature: try OWCodeSigning.inspect(at: url), error: nil)
            } catch {
                return SignatureInspectResult(signature: nil, error: "Signature inspect failed: \(error)")
            }
        }.value

        path = url
        binary = parsed.binary
        entropies = parsed.entropies
        signature = signed.signature
        selectedSliceIndex = 0
        lastRefresh = Date()
        let errors = [parsed.error, signed.error].compactMap { $0 }
        lastError = errors.isEmpty ? nil : errors.joined(separator: " · ")
    }

    /// Re-parse the current path including symbol tables. Called
    /// lazily when the user navigates to the Symbols section.
    func refreshSymbols() async {
        guard let url = path else { return }
        isLoading = true
        defer { isLoading = false }
        let bin = await Task.detached { () -> BinaryFile? in
            try? OWBinary.parse(at: url, includeSymbols: true)
        }.value
        if let bin {
            binary = bin
        }
    }

    /// Re-issue the parse for the current path (Refresh button).
    func reload() async {
        guard let url = path else { return }
        await load(url: url)
    }

    // MARK: - Filters

    /// Linked dylibs of the current slice (the M1.3 surface).
    var dylibsForCurrentSlice: [LoadCommand.Dylib] {
        guard let slice = currentSlice else { return [] }
        return slice.loadCommands.compactMap { command in
            if case let .dylib(payload) = command { return payload }
            return nil
        }
    }

    var rpathsForCurrentSlice: [String] {
        guard let slice = currentSlice else { return [] }
        return slice.loadCommands.compactMap { command in
            if case let .rpath(path) = command { return path }
            return nil
        }
    }

    var segmentsForCurrentSlice: [Segment] {
        guard let slice = currentSlice else { return [] }
        return slice.loadCommands.compactMap { command in
            if case let .segment(payload) = command { return payload }
            return nil
        }
    }

    var filteredSymbols: [Symbol] {
        guard let slice = currentSlice, let all = slice.symbols else { return [] }
        var working = all
        if symbolsExternalOnly {
            working = working.filter { $0.isExternal }
        }
        let needle = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty {
            working = working.filter { $0.name.localizedCaseInsensitiveContains(needle) }
        }
        return working
    }

    var filteredDylibs: [LoadCommand.Dylib] {
        let needle = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty { return dylibsForCurrentSlice }
        return dylibsForCurrentSlice.filter {
            $0.name.localizedCaseInsensitiveContains(needle)
        }
    }

    var entropiesForCurrentSlice: [SectionEntropy] {
        entropies.filter { $0.sliceIndex == selectedSliceIndex }
    }

    /// Number of sections with entropy > 7.0 — the "suspicious
    /// packing" signal `owlwatch inspect --entropy` flags.
    var highEntropySectionCount: Int {
        entropies.filter { $0.entropy > 7.0 }.count
    }
}

/// Internal result wrappers — Swift's tuple types are limited to two
/// fields under SwiftLint's `large_tuple` rule, and these fan-outs
/// carry three.
private struct BinaryParseResult: Sendable {
    let binary: BinaryFile?
    let entropies: [SectionEntropy]
    let error: String?
}

private struct SignatureInspectResult: Sendable {
    let signature: CodeSignature?
    let error: String?
}

/// Sections inside the Binary Inspector window. Mirrors the surface
/// the CLI's `inspect` + `verify` subcommands expose.
enum BinaryInspectorSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case loadCommands
    case segments
    case symbols
    case signature
    case entitlements

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .overview: return "Overview"
        case .loadCommands: return "Load Commands"
        case .segments: return "Segments"
        case .symbols: return "Symbols"
        case .signature: return "Signature"
        case .entitlements: return "Entitlements"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return "doc.text.magnifyingglass"
        case .loadCommands: return "shippingbox"
        case .segments: return "square.grid.3x3"
        case .symbols: return "function"
        case .signature: return "checkmark.seal"
        case .entitlements: return "key.horizontal"
        }
    }
}
