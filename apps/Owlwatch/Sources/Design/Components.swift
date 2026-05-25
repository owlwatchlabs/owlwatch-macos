import SwiftUI

/// Owlwatch design-system reusable views. Verbatim transcription of
/// `docs/DESIGN.md` §10 component specs; sections cite the relevant
/// subsection. Sizes in points; colors are §1 tokens; typography
/// per §3. Selection highlight is amber everywhere via the window
/// `.tint(.owlAmber)` — never the system blue.

// MARK: - §10.1 Sidebar nav row

/// Icon + label + right-aligned count. Color follows selection
/// (List binding handles that — this view stays plain).
struct SidebarRow: View {
    let section: AppSection
    var count: Int?

    var body: some View {
        Label {
            HStack {
                Text(section.title).font(.owlMono(13))
                Spacer()
                if let count {
                    Text(grouped(count))
                        .font(.owlMono(11))
                        .foregroundStyle(Color.owlTextDim)
                }
            }
        } icon: {
            Image(systemName: section.icon)
        }
    }
}

// MARK: - §10.2 Section header

/// Title Space Grotesk 16 owlText; sub-nav + filter + refresh
/// trailing; 0.5pt owlBorder bottom rule.
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.owlDisplay(16))
                .foregroundStyle(Color.owlText)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.owlBorder).frame(height: 0.5)
        }
    }
}

// MARK: - §10.3 Segmented sub-nav

/// Pills JBM 12. Inactive: owlTextMuted, border owlBorder. Active:
/// fill owlSurfaceHi, text owlAmber, border owlAmberDim. Replaces
/// the per-window sub-sidebars (All / Listeners / TCP …) from M16.
struct SubnavPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.0) { value, label in
                let on = value == selection
                Text(label)
                    .font(.owlMono(12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .foregroundStyle(on ? Color.owlAmber : Color.owlTextMuted)
                    .background(
                        on ? Color.owlSurfaceHi : .clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(on ? Color.owlAmberDim : Color.owlBorder, lineWidth: 0.5)
                    )
                    .onTapGesture { selection = value }
            }
        }
    }
}

// MARK: - §10.4 Filter field

/// Search field JBM 12; placeholder owlTextDim; fill owlSurfaceHi;
/// radius 7; leading magnifying glass.
struct FilterField: View {
    @Binding var text: String
    var placeholder: String = "Filter…"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.owlTextDim)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.owlMono(12))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.owlSurfaceHi, in: RoundedRectangle(cornerRadius: 7))
    }
}

// MARK: - §10.6 Signing status

/// Colored text (not a heavy chip). signed → owlAmber; verified /
/// active → owlGreen; unsigned / danger → owlRed; n/a → owlTextDim.
enum SigningStatus: Hashable {
    case signed(String)
    case verified
    case unsigned
    case na

    var label: String {
        switch self {
        case .signed(let value): return value
        case .verified:          return "verified"
        case .unsigned:          return "unsigned"
        case .na:                return "n/a"
        }
    }

    var color: Color {
        switch self {
        case .signed:   return .owlAmber
        case .verified: return .owlGreen
        case .unsigned: return .owlRed
        case .na:       return .owlTextDim
        }
    }
}

struct StatusPill: View {
    let status: SigningStatus

    init(_ status: SigningStatus) { self.status = status }

    var body: some View {
        Text(status.label)
            .font(.owlMono(11))
            .foregroundStyle(status.color)
    }
}

// MARK: - §10.5 Data list row

/// Two-line row. Line 1: identifier owlTextDim + name owlText +
/// trailing StatusPill. Line 2: path owlTextDim, truncate middle.
/// Pass a RAW identifier (use `raw(_:)` from Tokens.swift, never
/// `grouped(_:)`) — PIDs and ports must not be comma-formatted.
struct DataRow: View {
    let id: String
    let name: String
    let path: String?
    let status: SigningStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(id).foregroundStyle(Color.owlTextDim)
                Text(name).foregroundStyle(Color.owlText)
                Spacer()
                if let status { StatusPill(status) }
            }
            .font(.owlMono(13))
            if let path {
                Text(path)
                    .font(.owlMono(11))
                    .foregroundStyle(Color.owlTextDim)
                    .truncationMode(.middle)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
}

// MARK: - §10.7 Enabled / disabled badge

/// Subtle pill, JBM 11. enabled → owlGreen on 12% green; disabled →
/// owlTextDim on 12% dim. Used in the Persistence section.
struct StateBadge: View {
    let on: Bool

    var body: some View {
        Text(on ? "enabled" : "disabled")
            .font(.owlMono(11))
            .foregroundStyle(on ? Color.owlGreen : Color.owlTextDim)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                (on ? Color.owlGreen : Color.owlTextDim).opacity(0.12),
                in: RoundedRectangle(cornerRadius: 5)
            )
    }
}

// MARK: - §10.8 Linked cross-link row

/// Icon + label + trailing arrow, tinted by target type. Border
/// owlBorder, radius 7, JBM 12. The action closure typically sets
/// `AppModel.focus` and flips `AppModel.section` — see §6.
struct LinkedRow: View {
    let icon: String
    let label: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(label).font(.owlMono(12))
                Spacer()
                Image(systemName: "arrow.right")
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.owlBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - §10.9 Key–value table row

/// Label owlTextMuted (fixed 120pt column) + value owlText, both
/// JBM 12. `valueColor` overrides for parse-error lines (owlRed) or
/// status-coded values.
struct KeyValueRow: View {
    let key: String
    let value: String
    var valueColor: Color = .owlText

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .foregroundStyle(Color.owlTextMuted)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .foregroundStyle(valueColor)
            Spacer()
        }
        .font(.owlMono(12))
    }
}

// MARK: - §10.10 Empty state (quiet)

/// Small symbol owlTextDim + one muted line JBM 13. Replaces the
/// large "Select a …" headlines. Voice rule: "Select a {noun} to
/// see its details."
struct EmptyState: View {
    let text: String
    var symbol: String = "list.bullet"

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(Color.owlTextDim)
            Text(text)
                .font(.owlMono(13))
                .foregroundStyle(Color.owlTextMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
