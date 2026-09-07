import GRDB
import XCTest
@testable import KeepCore

final class MarkStoreTests: XCTestCase {
    func testLeftFilterHidesShortlistedAndPassed() throws {
        let db = try Catalog.open(at: FileManager.default.temporaryDirectory
            .appendingPathComponent("keep-marks-\(UUID().uuidString).sqlite"))
        try db.write { db in
            var a = PhotoRecord(photoID: "A", ceremony: "01", style: "Candid", camera: "A", canonicalPath: "A.jpg", canonicalKind: "jpeg")
            var b = PhotoRecord(photoID: "B", ceremony: "01", style: "Candid", camera: "A", canonicalPath: "B.jpg", canonicalKind: "jpeg")
            var c = PhotoRecord(photoID: "C", ceremony: "01", style: "Candid", camera: "A", canonicalPath: "C.jpg", canonicalKind: "jpeg")
            try a.insert(db)
            try b.insert(db)
            try c.insert(db)
        }
        let photos = try db.read { try PhotoRecord.order(Column("photoID")).fetchAll($0) }
        let store = MarkStore(db: db)
        try store.apply(photoPk: photos[0].id!, shortlisted: true, passed: false)
        try store.apply(photoPk: photos[1].id!, shortlisted: false, passed: true)

        let left = try PhotoQuery.visiblePhotos(db: db, ceremony: "01", style: "", view: .all, filter: .left)
        XCTAssertEqual(left.map(\.photoID), ["C"])

        let short = try PhotoQuery.visiblePhotos(db: db, ceremony: "01", style: "", view: .shortlist, filter: .everything)
        XCTAssertEqual(short.map(\.photoID), ["A"])

        let passed = try PhotoQuery.visiblePhotos(db: db, ceremony: "01", style: "", view: .all, filter: .passed)
        XCTAssertEqual(passed.map(\.photoID), ["B"])
    }

    func testUndoRestoresPriorMark() throws {
        let db = try Catalog.open(at: FileManager.default.temporaryDirectory
            .appendingPathComponent("keep-undo-\(UUID().uuidString).sqlite"))
        let pk = try db.write { db -> Int64 in
            var a = PhotoRecord(photoID: "A", ceremony: "01", style: "Candid", camera: "A", canonicalPath: "A.jpg", canonicalKind: "jpeg")
            try a.insert(db)
            return a.id!
        }
        let store = MarkStore(db: db)
        store.pushUndo(try store.snapshot(pk))
        try store.apply(photoPk: pk, shortlisted: true, passed: false)
        XCTAssertEqual(try store.mark(for: pk)?.shortlisted, true)
        _ = try store.popUndo()
        XCTAssertEqual(try store.mark(for: pk)?.shortlisted, false)
    }

    func testNotePersists() throws {
        let db = try Catalog.open(at: FileManager.default.temporaryDirectory
            .appendingPathComponent("keep-note-\(UUID().uuidString).sqlite"))
        let pk = try db.write { db -> Int64 in
            var a = PhotoRecord(photoID: "A", ceremony: "01", style: "Candid", camera: "A", canonicalPath: "A.jpg", canonicalKind: "jpeg")
            try a.insert(db)
            return a.id!
        }
        let store = MarkStore(db: db)
        try store.setNote(photoPk: pk, "  use this smile  ")
        XCTAssertEqual(try store.mark(for: pk)?.note, "use this smile")
        try store.setNote(photoPk: pk, "   ")
        XCTAssertNil(try store.mark(for: pk)?.note)
    }
}
