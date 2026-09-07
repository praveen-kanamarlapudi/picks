import KeepCore
import SwiftUI

/// Fills the size the parent proposes. Never grows to the original photo’s pixels.
struct ThumbView: View {
    let url: URL?
    var cacheKey: String = ""
    var cacheDir: URL?

    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.white.opacity(0.06)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            }
        }
        .clipShape(Rectangle())
        .contentShape(Rectangle())
        .task(id: "\(url?.path ?? "")-\(cacheKey)-\(cacheDir?.path ?? "")") {
            guard let url else {
                image = nil
                return
            }
            image = nil
            let key = cacheKey
            let dir = cacheDir
            let loaded = await Task.detached(priority: .utility) {
                if let dir, !key.isEmpty {
                    return Thumbnailer.cached(from: url, cacheDir: dir, key: key)
                }
                return Thumbnailer.thumbnail(from: url)
            }.value
            image = loaded
        }
    }
}
