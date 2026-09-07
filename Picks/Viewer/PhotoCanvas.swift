import AppKit
import SwiftUI

struct PhotoCanvas: View {
    let url: URL?
    @Binding var zoom: ZoomSession
    var cursor: CGPoint

    @State private var image: NSImage?
    @State private var loadID = UUID()
    @State private var dragOrigin: CGSize?

    var body: some View {
        GeometryReader { geo in
            let viewport = geo.size
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: viewport.width + 48, height: viewport.height + 48)
                        .blur(radius: 28)
                        .opacity(0.45)
                        .clipped()
                        .allowsHitTesting(false)
                }
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: viewport.width, height: viewport.height)
                        .scaleEffect(zoom.scale, anchor: .center)
                        .offset(zoom.pan)
                        .animation(.easeOut(duration: 0.14), value: zoom.step)
                } else {
                    ProgressView().tint(Theme.gold)
                }
            }
            .frame(width: viewport.width, height: viewport.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(panGesture(viewport: viewport, imageSize: image?.size ?? viewport))
            .simultaneousGesture(pinchGesture(viewport: viewport, imageSize: image?.size ?? viewport))
            .onAppear { report(viewport: viewport) }
            .onChange(of: viewport) { _, new in
                report(viewport: new)
                zoom.clamp(viewport: new, imageSize: image?.size ?? new)
            }
            .onChange(of: image?.size) { _, _ in
                if let image {
                    zoom.clamp(viewport: viewport, imageSize: image.size)
                }
            }
            .task(id: url?.path) {
                await loadFull()
            }
            .preference(key: ViewportPreference.self, value: viewport)
            .preference(key: ImageSizePreference.self, value: image?.size ?? .zero)
        }
    }

    private func pinchGesture(viewport: CGSize, imageSize: CGSize) -> some Gesture {
        MagnifyGesture()
            .onEnded { value in
                if value.magnification > 1.08 {
                    zoom.zoomIn(cursor: CGPoint(x: viewport.width / 2, y: viewport.height / 2), viewport: viewport, imageSize: imageSize)
                } else if value.magnification < 0.92 {
                    zoom.zoomOut(cursor: CGPoint(x: viewport.width / 2, y: viewport.height / 2), viewport: viewport, imageSize: imageSize)
                }
            }
    }

    private func panGesture(viewport: CGSize, imageSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard zoom.isZoomed else { return }
                if dragOrigin == nil { dragOrigin = zoom.pan }
                let origin = dragOrigin ?? .zero
                zoom.setPan(
                    CGSize(width: origin.width + value.translation.width, height: origin.height + value.translation.height),
                    viewport: viewport,
                    imageSize: imageSize
                )
            }
            .onEnded { _ in
                dragOrigin = nil
            }
    }

    private func report(viewport: CGSize) {
        _ = viewport
    }

    @MainActor
    private func loadFull() async {
        guard let url else {
            image = nil
            return
        }
        let id = UUID()
        loadID = id
        // Paint a small thumb first so flipping photos stays instant.
        let preview = await Task.detached(priority: .utility) {
            PhotoLoader.cheapThumb(at: url, maxPixel: 512)
        }.value
        if loadID == id, image == nil, let preview {
            image = preview
        }
        let full = await Task.detached(priority: .userInitiated) {
            PhotoLoader.fullImage(at: url)
        }.value
        if loadID == id {
            image = full ?? preview
        }
    }
}

struct ViewportPreference: PreferenceKey {
    static var defaultValue: CGSize { .zero }
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

struct ImageSizePreference: PreferenceKey {
    static var defaultValue: CGSize { .zero }
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
