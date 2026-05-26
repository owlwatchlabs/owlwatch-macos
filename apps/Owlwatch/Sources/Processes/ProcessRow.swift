import SwiftUI

/// One row in the M18.4 faceted process list.
///
/// Layout: 7-pt severity dot (visible only when rules matched) +
/// 2-line ident (name + raw pid on top, path on bottom) + signer
/// label + "N rules" trailer. Selection background is inherited
/// from List + .tint(.owlAmber).
struct ProcessRow: View {
    let row: ProcessRowVM

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(row.severityColor)
                .frame(width: 7, height: 7)
                .opacity(row.ruleCount > 0 ? 1 : 0)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(row.name)
                        .foregroundStyle(Color.owlText)
                    Text(raw(row.pid))
                        .foregroundStyle(Color.owlTextDim)
                }
                .font(.owlMono(12.5))

                if let path = row.path {
                    Text(path)
                        .font(.owlMono(11))
                        .foregroundStyle(Color.owlTextDim)
                        .truncationMode(.middle)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(row.signer.label)
                    .font(.owlMono(11))
                    .foregroundStyle(row.signer.color)
                if row.ruleCount > 0 {
                    Text("\(row.ruleCount) rule\(row.ruleCount == 1 ? "" : "s")")
                        .font(.owlMono(10.5))
                        .foregroundStyle(Color.owlTextDim)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
