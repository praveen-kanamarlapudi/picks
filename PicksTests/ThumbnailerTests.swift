import AppKit
import ImageIO
import XCTest
@testable import PicksCore

final class ThumbnailerTests: XCTestCase {
    func testLoupeDecodeKeepsFullPixelSize() throws {
        let big = try makeJPEG(width: 2400, height: 1800)
        defer { try? FileManager.default.removeItem(at: big) }
        let full = try XCTUnwrap(Thumbnailer.previewImage(from: big))
        XCTAssertGreaterThan(max(full.size.width, full.size.height), 1000)
        let thumb = try XCTUnwrap(Thumbnailer.thumbnail(from: big, maxPixel: 256))
        XCTAssertLessThan(max(thumb.size.width, thumb.size.height), 300)
    }

    func testThumbnailIsCappedAndNeverFullSize() throws {
        let big = try makeJPEG(width: 2400, height: 1800)
        defer { try? FileManager.default.removeItem(at: big) }
        let thumb = try XCTUnwrap(Thumbnailer.thumbnail(from: big, maxPixel: 256))
        XCTAssertLessThanOrEqual(max(thumb.size.width, thumb.size.height), 256 + 1)
    }

    func testCacheRoundTrip() throws {
        let big = try makeJPEG(width: 800, height: 600)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("thumbs-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: big)
            try? FileManager.default.removeItem(at: dir)
        }
        let first = try XCTUnwrap(Thumbnailer.cached(from: big, cacheDir: dir, key: "abc", maxPixel: 128))
        XCTAssertLessThanOrEqual(max(first.size.width, first.size.height), 128 + 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("abc.jpg").path))
        let second = try XCTUnwrap(Thumbnailer.cached(from: big, cacheDir: dir, key: "abc", maxPixel: 128))
        XCTAssertEqual(second.size.width, first.size.width, accuracy: 1)
    }

    func testMemoryCacheDoesNotBleedAcrossEvents() throws {
        let a = try makeJPEG(width: 400, height: 300, color: .red)
        let b = try makeJPEG(width: 400, height: 300, color: .blue)
        let dirA = FileManager.default.temporaryDirectory.appendingPathComponent("thumbs-a-\(UUID().uuidString)")
        let dirB = FileManager.default.temporaryDirectory.appendingPathComponent("thumbs-b-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: b)
            try? FileManager.default.removeItem(at: dirA)
            try? FileManager.default.removeItem(at: dirB)
        }
        let fromA = try XCTUnwrap(Thumbnailer.cached(from: a, cacheDir: dirA, key: "1", maxPixel: 64))
        let fromB = try XCTUnwrap(Thumbnailer.cached(from: b, cacheDir: dirB, key: "1", maxPixel: 64))
        XCTAssertNotEqual(fromA.tiffRepresentation, fromB.tiffRepresentation)
        let againA = try XCTUnwrap(Thumbnailer.cached(from: a, cacheDir: dirA, key: "1", maxPixel: 64))
        XCTAssertEqual(againA.tiffRepresentation, fromA.tiffRepresentation)
    }

    private func makeJPEG(width: Int, height: Int, color: NSColor = .gray) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("big-\(UUID().uuidString).jpg")
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let data = try XCTUnwrap(rep.representation(using: .jpeg, properties: [:]))
        try data.write(to: url)
        return url
    }
}