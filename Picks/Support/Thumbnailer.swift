import AppKit
import Foundation
import ImageIO

/// Small stills for grid / filmstrip. Never returns a full-resolution original.
public enum Thumbnailer: Sendable {
    public static let gridPixel = 256

    public static func thumbnail(from source: URL, maxPixel: Int = gridPixel) -> NSImage? {
        decode(from: source, maxPixel: maxPixel)
    }

    /// Full-resolution still, EXIF/TIFF orientation applied — same upright result as Preview.
    public static func previewImage(from source: URL) -> NSImage? {
        decode(from: source, maxPixel: nil)
    }

    /// `maxPixel == nil` keeps every pixel. ImageIO's thumbnail API is used because
    /// `CreateImageAtIndex` ignores orientation and lays portrait shots on their side.
    private static func decode(from source: URL, maxPixel: Int?) -> NSImage? {
        let opts: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let src = CGImageSourceCreateWithURL(source as CFURL, opts as CFDictionary) else {
            return nil
        }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let pixelW = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let pixelH = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let native = max(pixelW, pixelH, 1)
        let cap = maxPixel ?? native
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: cap,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    public static func clearMemory() {
        ThumbMemory.shared.removeAll()
    }

    public static func cached(
        from source: URL,
        cacheDir: URL,
        key: String,
        maxPixel: Int = gridPixel
    ) -> NSImage? {
        let safe = sanitize(key)
        // Disk is per-event already. Memory was only keyed by row ID, so dump A’s
        // photo 1 was shown for dump B’s photo 1 after switching events.
        let mem = "\(cacheDir.path)/\(safe)"
        if let hit = ThumbMemory.shared.image(for: mem) { return hit }

        let file = cacheDir.appendingPathComponent("\(safe).jpg")
        if let existing = NSImage(contentsOf: file), existing.size.width > 1 {
            ThumbMemory.shared.store(existing, for: mem)
            return existing
        }

        DecodeGate.shared.wait()
        defer { DecodeGate.shared.signal() }

        if let hit = ThumbMemory.shared.image(for: mem) { return hit }
        guard let image = decode(from: source, maxPixel: maxPixel) else { return nil }
        ThumbMemory.shared.store(image, for: mem)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
            try? jpeg.write(to: file, options: .atomic)
        }
        return image
    }

    private static func sanitize(_ key: String) -> String {
        key.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }
}

/// At most a few ImageIO jobs at once so opening Engagement does not spawn 2,700 decodes.
final class DecodeGate: @unchecked Sendable {
    static let shared = DecodeGate()
    private let sema = DispatchSemaphore(value: 3)
    func wait() { sema.wait() }
    func signal() { sema.signal() }
}

final class ThumbMemory: @unchecked Sendable {
    static let shared = ThumbMemory()
    private let cache = NSCache<NSString, NSImage>()
    private init() {
        cache.countLimit = 400
        cache.totalCostLimit = 80 * 1024 * 1024
    }
    func image(for key: String) -> NSImage? { cache.object(forKey: key as NSString) }
    func store(_ image: NSImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
    func removeAll() { cache.removeAllObjects() }
}
