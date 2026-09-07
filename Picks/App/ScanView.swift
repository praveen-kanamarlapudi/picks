import SwiftUI

struct ScanView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Scanning")
                .font(.system(size: 26, weight: .medium))
            Text(model.eventName)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            ProgressView()
                .progressViewStyle(.linear)
                .tint(Theme.gold)
                .padding(.vertical, 8)
            stat("Walking files", model.scanMessage)
            stat("Stills found so far", "—")
            Text("Pairing JPEG + RAW. Canonical is RAW whenever it exists.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
                .padding(.top, 8)
        }
        .frame(maxWidth: 480)
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(Theme.muted)
        }
        .font(.system(size: 13))
    }
}
