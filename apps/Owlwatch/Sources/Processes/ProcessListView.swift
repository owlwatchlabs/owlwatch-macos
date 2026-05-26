import SwiftUI

/// The M18.4 faceted process list — left pane of the Processes
/// section. Replaces the M17.4 SubnavPicker (All/Tree) + flat-list
/// layout with the triage-first design: a free-text filter field, a
/// wrapping row of facet chips with live counts, salience sort, and
/// signer-colored rows.
///
/// The right pane (detail / dossier) is owned by `ProcessesView`
/// and stays on the M17.4 ProcessesDetailPane until M18.5 lands.
struct ProcessListView: View {
    @ObservedObject var model: ProcessListModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            FilterField(text: $model.query,
                        placeholder: "Filter by name, path, PID, team ID…")
            FacetFlow(
                facets: ProcessFacet.allCases,
                active: $model.active,
                counts: Dictionary(
                    uniqueKeysWithValues: ProcessFacet.allCases.map { ($0, model.count($0)) }
                )
            )
            statusRow
            Divider().overlay(Color.owlBorder)
            listBody
        }
        .padding(16)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Processes")
                .font(.owlDisplay(16))
                .foregroundStyle(Color.owlText)
            Spacer()
            Text("\(grouped(model.rows.count)) running")
                .font(.owlMono(11))
                .foregroundStyle(Color.owlTextDim)
        }
    }

    // MARK: - Status row

    @ViewBuilder
    private var statusRow: some View {
        let visibleCount = model.visible.count
        HStack {
            Text("sort: severity (rules first)")
                .font(.owlMono(10.5))
                .foregroundStyle(Color.owlTextMuted)
            Spacer()
            if !model.active.isEmpty {
                Text(
                    "\(model.active.count) filter\(model.active.count == 1 ? "" : "s") · " +
                    "\(grouped(visibleCount)) match\(visibleCount == 1 ? "" : "es")"
                )
                .font(.owlMono(10.5))
                .foregroundStyle(Color.owlAmber)
            }
        }
    }

    // MARK: - List

    @ViewBuilder
    private var listBody: some View {
        let visible = model.visible
        if model.isLoading && visible.isEmpty {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading processes…")
                    .font(.owlMono(11))
                    .foregroundStyle(Color.owlTextMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visible.isEmpty {
            EmptyState(
                text: model.query.isEmpty && model.active.isEmpty
                    ? "No processes found."
                    : "No processes match these filters.",
                symbol: "cpu"
            )
        } else {
            List(visible, selection: $model.selection) { row in
                ProcessRow(row: row).tag(row.pid)
            }
            .listStyle(.plain)
        }
    }
}
