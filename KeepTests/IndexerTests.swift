import GRDB
import XCTest
@testable import KeepCore

final class IndexerTests: XCTestCase {
    func testScanMiniDump() throws {
        let root = try makeMiniDump()
        defer { try? FileManager.default.removeItem(at: root) }

        let dbURL = root.appendingPathComponent("catalog.sqlite")
        let db = try Catalog.open(at: dbURL)
        let stats = try Indexer.scan(root: root, db: db)

        XCTAssertEqual(stats.videosIgnored, 1)
        XCTAssertEqual(stats.videoThumbsSkipped, 1)
        XCTAssertEqual(stats.stills, 3)

        let photos = try db.read { try PhotoRecord.order(Column("photoID")).fetchAll($0) }
        XCTAssertEqual(photos.count, 3)

        let akhi = photos.first { $0.photoID == "AKHI0001" }
        XCTAssertEqual(akhi?.canonicalKind, "jpeg")
        XCTAssertNil(akhi?.rawPath)

        let paired = photos.first { $0.photoID == "M3F0001" }
        XCTAssertEqual(paired?.canonicalKind, "raw")
        XCTAssertEqual(paired?.canonicalPath, "03 Wedding/Candid Photos/RAW/M3F0001.ARW")
        XCTAssertNotNil(paired?.jpegPath)

        let rawOnly = photos.first { $0.photoID == "M3F0002" }
        XCTAssertEqual(rawOnly?.canonicalKind, "raw")
        XCTAssertNil(rawOnly?.jpegPath)
    }

    func testMarksPersistAcrossReopen() throws {
        let root = try makeMiniDump()
        defer { try? FileManager.default.removeItem(at: root) }
        let dbURL = root.appendingPathComponent("catalog.sqlite")
        let db = try Catalog.open(at: dbURL)
        _ = try Indexer.scan(root: root, db: db)

        let photo = try db.read { try PhotoRecord.filter(Column("photoID") == "AKHI0001").fetchOne($0) }
        let pk = try XCTUnwrap(photo?.id)
        let store = MarkStore(db: db)
        try store.apply(photoPk: pk, shortlisted: true, passed: false)

        let db2 = try Catalog.open(at: dbURL)
        let mark = try db2.read { try MarkRecord.fetchOne($0, key: pk) }
        XCTAssertEqual(mark?.shortlisted, true)
    }

    func testRescanPreservesShortlistByPhotoID() throws {
        let root = try makeMiniDump()
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try Catalog.open(at: root.appendingPathComponent("catalog.sqlite"))
        _ = try Indexer.scan(root: root, db: db)
        let before = try db.read { try PhotoRecord.filter(Column("photoID") == "AKHI0001").fetchOne($0) }
        let pk = try XCTUnwrap(before?.id)
        try MarkStore(db: db).apply(photoPk: pk, shortlisted: true, passed: false)

        _ = try Indexer.scan(root: root, db: db)
        let after = try db.read { try PhotoRecord.filter(Column("photoID") == "AKHI0001").fetchOne($0) }
        let newPk = try XCTUnwrap(after?.id)
        let mark = try db.read { try MarkRecord.fetchOne($0, key: newPk) }
        XCTAssertEqual(mark?.shortlisted, true)
        XCTAssertEqual(try db.read { try MarkRecord.filter(Column("shortlisted") == true).fetchCount($0) }, 1)
    }

    func testCollapseMisindexedFlatDump() throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("keep-flat-\(UUID().uuidString).sqlite")
        let db = try Catalog.open(at: dbURL)
        try db.write { db in
            var a = PhotoRecord(
                photoID: "SAB09390",
                ceremony: "SAB09390.JPG",
                style: "Other",
                camera: "SAB",
                canonicalPath: "SAB09390.JPG",
                canonicalKind: "jpeg"
            )
            var b = PhotoRecord(
                photoID: "SAB09395",
                ceremony: "SAB09395.JPG",
                style: "Other",
                camera: "SAB",
                canonicalPath: "SAB09395.JPG",
                canonicalKind: "jpeg"
            )
            try a.insert(db)
            try b.insert(db)
            var session = try SessionRecord.find(db, key: 1) ?? SessionRecord()
            session.ceremony = "SAB09390.JPG"
            try session.update(db)
        }
        try Indexer.collapseMisindexedFlatDump(db: db, eventName: "Newborn Photoshoot Raw")
        let ceremonies = try db.read { try String.fetchAll($0, sql: "SELECT DISTINCT ceremony FROM photos") }
        XCTAssertEqual(ceremonies, ["Newborn Photoshoot Raw"])
        let session = try PhotoQuery.loadSession(db: db)
        XCTAssertEqual(session.ceremony, "Newborn Photoshoot Raw")
    }

    func testCollapseLeavesNestedDumpsAlone() throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("keep-nested-\(UUID().uuidString).sqlite")
        let db = try Catalog.open(at: dbURL)
        try db.write { db in
            var a = PhotoRecord(
                photoID: "AKHI0001",
                ceremony: "01 Engagement",
                style: "Candid",
                camera: "AKHI",
                canonicalPath: "01 Engagement/Candid Photos/JPG/AKHI0001.JPG",
                canonicalKind: "jpeg"
            )
            try a.insert(db)
        }
        try Indexer.collapseMisindexedFlatDump(db: db, eventName: "WEDDING")
        let ceremony = try db.read { try String.fetchOne($0, sql: "SELECT ceremony FROM photos") }
        XCTAssertEqual(ceremony, "01 Engagement")
    }

    private func makeMiniDump() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeepMini-\(UUID().uuidString)", isDirectory: true)
        let paths = [
            "01 Engagement/Candid Photos/JPG/AKHI0001.JPG",
            "03 Wedding/Candid Photos/JPG/M3F0001.jpg",
            "03 Wedding/Candid Photos/RAW/M3F0001.ARW",
            "03 Wedding/Candid Photos/RAW/M3F0002.ARW",
            "03 Wedding/Traditional Video/Thumbnails/C0001T01.JPG",
            "03 Wedding/Candid Video/C0001.MP4",
        ]
        for rel in paths {
            let url = rel.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
        return root
    }
}
