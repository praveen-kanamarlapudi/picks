import KeepCore
import SwiftUI

struct GridView: View {
    @Environment(AppModel.self) private var model

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 6)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(model.photos, id: \.tileID) { photo in
                        tile(photo)
                            .id(photo.tileID)
                    }
                }
                .padding(2)
            }
            .scrollIndicators(.visible)
            .onChange(of: model.current?.tileID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .background(Theme.bg)
        .background(AlwaysShowScrollers())
    }

    private func tile(_ photo: PhotoRecord) -> some View {
        let on = photo.id == model.current?.id
        let starred = model.isShortlisted(photo)
        return Button {
            if photo.id == model.current?.id {
                model.showGrid = false
            } else {
                model.selectPhoto(photo)
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                ThumbView(
                    url: model.canonicalURL(for: photo),
                    cacheKey: photo.canonicalPath,
                    cacheDir: model.thumbCacheDir
                )

                if starred {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.black)
                        .padding(3)
                        .background(Theme.gold, in: Circle())
                        .padding(6)
                }
                VStack {
                    Spacer()
                    HStack {
                        Text(photo.photoID)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white) // on photo, keep white
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .top, endPoint: .bottom))
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(on ? Theme.text : Color.clear, lineWidth: 2))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .contentShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }
}
