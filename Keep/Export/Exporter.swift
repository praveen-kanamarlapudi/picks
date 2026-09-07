import AppKit
import Foundation
import GRDB

public struct ExportRow: Sendable, Equatable {
    public var id: String
    public var event: String
    public var ceremony: String
    public var style: String
    public var camera: String
    public var canonicalKind: String
    public var jpeg: String
    public var raw: String
    public var note: String
}

public enum Exporter: Sendable {
    public static func rows(
        db: DatabaseQueue,
        eventName: String,
        ceremony: String? = nil,
        style: String? = nil
    ) throws -> [ExportRow] {
        try db.read { conn in
            let photos = try PhotoQuery.shortlist(db: conn, ceremony: ceremony, style: style)
            let marks = Dictionary(uniqueKeysWithValues: try MarkRecord.fetchAll(conn).map { ($0.photoPk, $0) })
            return rows(photos: photos, marks: marks, eventName: eventName)
        }
    }

    public static func rows(photos: [PhotoRecord], marks: [Int64: MarkRecord], eventName: String) -> [ExportRow] {
        photos.map { photo in
            let note = photo.id.flatMap { marks[$0]?.note } ?? ""
            return ExportRow(
                id: photo.photoID,
                event: eventName,
                ceremony: photo.ceremony,
                style: photo.style,
                camera: photo.camera,
                canonicalKind: photo.canonicalKind,
                jpeg: photo.jpegPath ?? "",
                raw: photo.rawPath ?? "",
                note: note
            )
        }
    }

    public static func idsText(_ rows: [ExportRow]) -> String {
        rows.map(\.id).joined(separator: "\n")
    }

    public static func csv(_ rows: [ExportRow]) -> String {
        let header = "id,event,ceremony,style,camera,canonical_kind,jpeg,raw,note"
        let body = rows.map { row in
            [row.id, row.event, row.ceremony, row.style, row.camera, row.canonicalKind, row.jpeg, row.raw, row.note]
                .map(csvEscape)
                .joined(separator: ",")
        }
        return ([header] + body).joined(separator: "\n") + "\n"
    }

    public static func copyIDs(_ rows: [ExportRow]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(idsText(rows), forType: .string)
    }

    public static func write(rows: [ExportRow], to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try idsText(rows).write(to: folder.appendingPathComponent("photo-ids.txt"), atomically: true, encoding: .utf8)
        try csv(rows).write(to: folder.appendingPathComponent("shortlist.csv"), atomically: true, encoding: .utf8)
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
