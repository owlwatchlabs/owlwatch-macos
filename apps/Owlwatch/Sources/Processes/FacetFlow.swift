import SwiftUI

/// Wrapping flow of facet chips. Each chip toggles its facet's
/// membership in the bound `active` set; active chips render with
/// the amber stand-out style, inactive chips recede.
///
/// Built on a `Layout` (macOS 13+) so chips wrap naturally as the
/// pane resizes — no hardcoded widths.
struct FacetFlow: View {
    let facets: [ProcessFacet]
    @Binding var active: Set<ProcessFacet>
    /// Pre-resolved counts per facet. Passed as a value (not a
    /// closure) so SwiftUI's struct-diffing sees fresh chip values
    /// when the model's row set updates — a closure-typed property
    /// is opaque to diffing and the chips ended up rendering with
    /// stale (zero) counts.
    let counts: [ProcessFacet: Int]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(facets) { facet in
                FacetChip(
                    facet: facet,
                    isActive: active.contains(facet),
                    count: counts[facet] ?? 0
                ) {
                    if active.contains(facet) {
                        active.remove(facet)
                    } else {
                        active.insert(facet)
                    }
                }
            }
        }
    }
}

private struct FacetChip: View {
    let facet: ProcessFacet
    let isActive: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(facet.label).font(.owlMono(12))
                Text(grouped(count))
                    .font(.owlMono(11))
                    .foregroundStyle(isActive ? Color.owlAmber : .owlTextDim)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(isActive ? Color.owlAmber : .owlTextMuted)
            .background(
                isActive ? Color.owlSurfaceHi : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? Color.owlAmberDim : Color.owlBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Simple horizontal flow with wrapping. Lays subviews left-to-right,
/// wrapping to a new row when the next subview would overflow the
/// container width.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = layoutRows(in: maxWidth, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + CGFloat(max(rows.count - 1, 0)) * spacing
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = layoutRows(in: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for entry in row.items {
                let pos = CGPoint(x: x, y: y)
                entry.subview.place(
                    at: pos,
                    proposal: ProposedViewSize(width: entry.size.width, height: entry.size.height)
                )
                x += entry.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    // MARK: - Layout math

    private struct Row {
        var items: [(subview: LayoutSubview, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layoutRows(in maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let projected = rows[rows.count - 1].width
                + (rows[rows.count - 1].items.isEmpty ? 0 : spacing)
                + size.width
            if projected > maxWidth, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            var last = rows[rows.count - 1]
            if !last.items.isEmpty { last.width += spacing }
            last.items.append((subview, size))
            last.width += size.width
            last.height = max(last.height, size.height)
            rows[rows.count - 1] = last
        }
        return rows
    }
}
