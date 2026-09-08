import XCTest
@testable import PicksCore

final class DiskTrashTests: XCTestCase {
    func testTrashAndRestoreRoundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("picks-trash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let jpeg = dir.appendingPathComponent("M3F0001.jpg")
        let raw = dir.appendingPathComponent("M3F0001.ARW")
        try Data("jpeg".utf8).write(to: jpeg)
        try Data("raw".utf8).write(to: raw)

        let photo = PhotoRecord(
            photoID: "M3F0001",
            ceremony: "03 Wedding",
            style: "Traditional",
            camera: "M3F",
            canonicalPath: "M3F0001.ARW",
            canonicalKind: "raw",
            jpegPath: "M3F0001.jpg",
            rawPath: "M3F0001.ARW"
        )
        let urls = DiskTrash.urls(for: photo, root: dir)
        XCTAssertEqual(Set(urls.map(\.lastPathComponent)), ["M3F0001.jpg", "M3F0001.ARW"])

        let map = try await DiskTrash.trash(urls, dumpRoot: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: jpeg.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: raw.path))
        XCTAssertEqual(map.count, 2)

        try DiskTrash.restore(map)
        XCTAssertEqual(try String(contentsOf: jpeg, encoding: .utf8), "jpeg")
        XCTAssertEqual(try String(contentsOf: raw, encoding: .utf8), "raw")
    }

    func testInsertPreservingID() throws {
        let db = try Catalog.open(at: FileManager.default.temporaryDirectory
            .appendingPathComponent("picks-trash-id-\(UUID().uuidString).sqlite"))
        let pk = try db.write { db -> Int64 in
            var row = PhotoRecord(
                photoID: "A",
                ceremony: "01",
                style: "Other",
                camera: "A",
                canonicalPath: "A.jpg",
                canonicalKind: "jpeg"
            )
            try row.insert(db)
            return row.id!
        }
        try db.write { db in
            _ = try PhotoRecord.deleteOne(db, key: pk)
            let row = PhotoRecord(
                id: pk,
                photoID: "A",
                ceremony: "01",
                style: "Other",
                camera: "A",
                canonicalPath: "A.jpg",
                canonicalKind: "jpeg"
            )
            try DiskTrash.insertPreservingID(row, db: db)
        }
        let restored = try db.read { try PhotoRecord.fetchOne($0, key: pk) }
        XCTAssertEqual(restored?.photoID, "A")
        XCTAssertEqual(restored?.id, pk)
    }

    func testVolumeTrashFallbackIsUndoable() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("picks-trash-fb-\(UUID().uuidString)", isDirectory: true)
        let nested = dir.appendingPathComponent("Traditional Photos/RAW", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let raw = nested.appendingPathComponent("DSC00003.ARW")
        try Data("raw".utf8).write(to: raw)
        let dest = try DiskTrash.moveToVolumeTrash(raw)
        XCTAssertFalse(FileManager.default.fileExists(atPath: raw.path))
        XCTAssertTrue(dest.path.contains(".Trash"))
        XCTAssertEqual(try String(contentsOf: dest, encoding: .utf8), "raw")

        try DiskTrash.restore([raw: dest])
        XCTAssertEqual(try String(contentsOf: raw, encoding: .utf8), "raw")
    }
}
