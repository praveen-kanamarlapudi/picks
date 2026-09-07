import SwiftUI

struct OpenView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 10) {
                Text("Keep")
                    .font(.system(size: 36, weight: .medium, design: .default))
                    .tracking(-0.8)
                Text("Open a photo dump. RAW is the photo when it exists.\nJPEG only if there is no RAW.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            Button("Choose folder…") { model.chooseFolder() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Theme.gold)
                .foregroundStyle(Color.black)

            if !model.recents.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent")
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                        .textCase(.uppercase)
                    ForEach(model.recents.prefix(6)) { item in
                        Button {
                            model.openRecent(item)
                        } label: {
                            HStack {
                                Text(item.name)
                                    .foregroundStyle(Theme.text)
                                Spacer()
                                Text(item.lastOpened.formatted(date: .abbreviated, time: .omitted))
                                    .foregroundStyle(Theme.dim)
                                    .font(.caption)
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 420)
                .padding(.top, 12)
            }
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}
