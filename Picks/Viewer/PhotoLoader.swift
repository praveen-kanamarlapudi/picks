import AppKit
import Foundation
import ImageIO
import PicksCore

enum PhotoLoader: Sendable {
    /// Full Preview-quality decode. Same path Preview uses: the complete JPEG, or the
    /// camera-embedded preview inside a RAW. Never a downsampled thumbnail.
    static func fullImage(at url: URL) -> NSImage? {
        Thumbnailer.previewImage(from: url)
    }

    /// Downsampled decode for a first paint only. Loupe replaces this with `fullImage`.
    static func image(at url: URL, maxPixel: CGFloat) -> NSImage? {
        Thumbnailer.thumbnail(from: url, maxPixel: Int(max(maxPixel, 1)))
    }

    static func cheapThumb(at url: URL, maxPixel: CGFloat = 256) -> NSImage? {
        Thumbnailer.thumbnail(from: url, maxPixel: Int(maxPixel))
    }
}
