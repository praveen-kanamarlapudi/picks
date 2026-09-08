import XCTest
@testable import PicksCore

final class EventBookmarkTests: XCTestCase {
    func testSaveAndResolveRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("picks-bookmark-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let id = "test-\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: dir)
            if let eventDir = try? SupportPaths.eventDirectory(id: id) {
                try? FileManager.default.removeItem(at: eventDir)
            }
        }

        try EventBookmark.save(root: dir, eventID: id)
        let resolved = try EventBookmark.resolve(eventID: id)
        XCTAssertEqual(
            resolved.standardizedFileURL.resolvingSymlinksInPath().path,
            dir.standardizedFileURL.resolvingSymlinksInPath().path
        )
    }

    func testPlainBookmarkResolvesWhenSecurityScopeFails() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("picks-bookmark-plain-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let data = try dir.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        var stale = false
        do {
            _ = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            // Some hosts accept scoped resolve of a plain bookmark. Fallback still must work.
        } catch {
            // Expected on unsandboxed Picks with old Keep bookmarks.
        }
        let resolved = try EventBookmark.resolveBookmarkData(data, stale: &stale)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved.path))
        XCTAssertEqual(
            resolved.standardizedFileURL.resolvingSymlinksInPath().path,
            dir.standardizedFileURL.resolvingSymlinksInPath().path
        )
    }
}
