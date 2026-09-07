import XCTest
@testable import KeepCore
import GRDB

final class ExporterTests: XCTestCase {
    func testCSVAndIDsOrderByCeremony() {
        let photos = [
            PhotoRecord(id: 1, photoID: "M3F0001", ceremony: "03 Wedding", style: "Candid", camera: "M3F", canonicalPath: "a.ARW", canonicalKind: "raw", jpegPath: "a.jpg", rawPath: "a.ARW"),
            PhotoRecord(id: 2, photoID: "AKHI0001", ceremony: "01 Engagement", style: "Candid", camera: "AKHI", canonicalPath: "b.jpg", canonicalKind: "jpeg", jpegPath: "b.jpg"),
        ]
        let rows = Exporter.rows(photos: photos, marks: [:], eventName: "WEDDING")
        XCTAssertEqual(Exporter.idsText(rows), "M3F0001\nAKHI0001")
        let csv = Exporter.csv(rows)
        XCTAssertTrue(csv.contains("id,event,ceremony,style,camera,canonical_kind,jpeg,raw,note"))
        XCTAssertTrue(csv.contains("AKHI0001,WEDDING,01 Engagement"))
        XCTAssertTrue(csv.contains("raw"))
    }

    func testShortlistQuery() throws {
        let db = try Catalog.open(at: FileManager.default.temporaryDirectory
            .appendingPathComponent("keep-export-\(UUID().uuidString).sqlite"))
        try db.write { db in
            var a = PhotoRecord(photoID: "B", ceremony: "02", style: "Candid", camera: "B", canonicalPath: "B.jpg", canonicalKind: "jpeg")
            var b = PhotoRecord(photoID: "A", ceremony: "01", style: "Candid", camera: "A", canonicalPath: "A.jpg", canonicalKind: "jpeg")
            try a.insert(db)
            try b.insert(db)
            try MarkRecord(photoPk: a.id!, shortlisted: true).insert(db)
            try MarkRecord(photoPk: b.id!, shortlisted: true).insert(db)
        }
        let list = try PhotoQuery.shortlist(db: db)
        XCTAssertEqual(list.map(\.photoID), ["A", "B"])
        let only01 = try PhotoQuery.shortlist(db: db, ceremony: "01")
        XCTAssertEqual(only01.map(\.photoID), ["A"])
        let rows = try Exporter.rows(db: db, eventName: "E")
        XCTAssertEqual(rows.map(\.id), ["A", "B"])
    }

    func testCeremonyStatsCounts() throws {
        let db = try Catalog.open(at: FileManager.default.temporaryDirectory
            .appendingPathComponent("keep-stats-\(UUID().uuidString).sqlite"))
        try db.write { db in
            var a = PhotoRecord(photoID: "A1", ceremony: "01 Engagement", style: "Candid", camera: "A", canonicalPath: "A1.jpg", canonicalKind: "jpeg")
            var b = PhotoRecord(photoID: "A2", ceremony: "01 Engagement", style: "Candid", camera: "A", canonicalPath: "A2.jpg", canonicalKind: "jpeg")
            try a.insert(db)
            try b.insert(db)
            try MarkRecord(photoPk: a.id!, shortlisted: true).insert(db)
        }
        let cards = try PhotoQuery.ceremonyStats(db: db)
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].stills, 2)
        XCTAssertEqual(cards[0].shortlisted, 1)
        XCTAssertEqual(cards[0].left, 1)
        XCTAssertEqual(cards[0].style, "Candid")
    }

    func testCeremonyStatsSplitsCandidAndTraditional() throws {
        let db = try Catalog.open(at: FileManager.default.temporaryDirectory
            .appendingPathComponent("keep-styles-\(UUID().uuidString).sqlite"))
        try db.write { db in
            var a = PhotoRecord(photoID: "C1", ceremony: "01 Engagement", style: "Candid", camera: "A", canonicalPath: "c.jpg", canonicalKind: "jpeg")
            var b = PhotoRecord(photoID: "T1", ceremony: "01 Engagement", style: "Traditional", camera: "A", canonicalPath: "t.jpg", canonicalKind: "jpeg")
            try a.insert(db)
            try b.insert(db)
        }
        let cards = try PhotoQuery.ceremonyStats(db: db)
        XCTAssertEqual(cards.map(\.style), ["Traditional", "Candid"])
        XCTAssertEqual(cards.map(\.stills), [1, 1])
    }
}
