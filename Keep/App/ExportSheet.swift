import KeepCore
import SwiftUI

struct ExportSheet: View {
    @Environment(AppModel.self) private var model

    private var rows: [ExportRow] { model.exportRows() }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export \(rows.count) photos")
                .font(.system(size: 20, weight: .medium))
            Text("Current pile: \(model.exportScopeLabel). Copy IDs sends only these.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)

            row(title: "photo-ids.txt", detail: previewIDs, on: true)
            row(title: "shortlist.csv", detail: "id, event, ceremony, style, camera, jpeg, raw, note", on: true)
            row(title: "contact-sheet.pdf", detail: "6-up with IDs. Not in this build.", on: false)

            HStack {
                Spacer()
                Button(model.exportCopied ? "Copied" : "Copy IDs") {
                    model.copyExportIDs()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Save to folder…") { model.saveExport() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.gold)
                    .foregroundStyle(.black)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 460)
        .background(Theme.bg)
        .onAppear { model.exportCopied = false }
    }

    private var previewIDs: String {
        let ids = rows.prefix(8).map(\.id)
        if rows.count > 8 { return ids.joined(separator: " · ") + " …" }
        return ids.isEmpty ? "Nothing shortlisted yet" : ids.joined(separator: " · ")
    }

    private func row(title: String, detail: String, on: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: on ? "checkmark.square.fill" : "square")
                .foregroundStyle(on ? Theme.gold : Theme.dim)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Divider().opacity(0.3) }
    }
}
