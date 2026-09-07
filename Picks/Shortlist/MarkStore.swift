import Foundation
import GRDB

public struct MarkSnapshot: Sendable, Equatable {
    public var photoPk: Int64
    public var shortlisted: Bool
    public var passed: Bool
}

public final class MarkStore: @unchecked Sendable {
    private let db: DatabaseQueue
    private var undo: [MarkSnapshot] = []

    public init(db: DatabaseQueue) {
        self.db = db
    }

    public func mark(for photoPk: Int64) throws -> MarkRecord? {
        try db.read { db in
            try MarkRecord.fetchOne(db, key: photoPk)
        }
    }

    public func marksByPhoto() throws -> [Int64: MarkRecord] {
        try db.read { db in
            Dictionary(uniqueKeysWithValues: try MarkRecord.fetchAll(db).map { ($0.photoPk, $0) })
        }
    }

    @discardableResult
    public func apply(photoPk: Int64, shortlisted: Bool?, passed: Bool?, pushUndo: Bool = true) throws -> MarkRecord {
        try db.write { db in
            var row = try MarkRecord.fetchOne(db, key: photoPk)
                ?? MarkRecord(photoPk: photoPk)
            if pushUndo {
                // undo captured by caller usually; keep last state here too
            }
            if let shortlisted {
                row.shortlisted = shortlisted
                if shortlisted { row.passed = false }
            }
            if let passed {
                row.passed = passed
                if passed { row.shortlisted = false }
            }
            row.updatedAt = ISO8601DateFormatter().string(from: Date())
            try row.save(db)
            return row
        }
    }

    @discardableResult
    public func setNote(photoPk: Int64, _ note: String?) throws -> MarkRecord {
        try db.write { db in
            var row = try MarkRecord.fetchOne(db, key: photoPk) ?? MarkRecord(photoPk: photoPk)
            let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            row.note = (trimmed?.isEmpty == false) ? trimmed : nil
            row.updatedAt = ISO8601DateFormatter().string(from: Date())
            try row.save(db)
            return row
        }
    }

    public func pushUndo(_ snap: MarkSnapshot) {
        undo.append(snap)
        if undo.count > 200 { undo.removeFirst(undo.count - 200) }
    }

    public func popUndo() throws -> MarkSnapshot? {
        guard let snap = undo.popLast() else { return nil }
        try apply(photoPk: snap.photoPk, shortlisted: snap.shortlisted, passed: snap.passed, pushUndo: false)
        return snap
    }

    public func snapshot(_ photoPk: Int64) throws -> MarkSnapshot {
        let row = try mark(for: photoPk)
        return MarkSnapshot(
            photoPk: photoPk,
            shortlisted: row?.shortlisted ?? false,
            passed: row?.passed ?? false
        )
    }
}

public enum PhotoQuery {
    public static func visiblePhotos(
        db: DatabaseQueue,
        ceremony: String,
        style: String,
        view: ReviewViewMode,
        filter: AllFilter
    ) throws -> [PhotoRecord] {
        try db.read { db in
            var request = PhotoRecord
                .filter(Column("ceremony") == ceremony)
                .filter(Column("hiddenDup") == false)
            if !style.isEmpty {
                request = request.filter(Column("style") == style)
            }
            let photos = try request
                .order(Column("photoID"))
                .fetchAll(db)
            let marks = Dictionary(uniqueKeysWithValues: try MarkRecord.fetchAll(db).map { ($0.photoPk, $0) })
            return photos.filter { photo in
                guard let pk = photo.id else { return false }
                let mark = marks[pk]
                let shortlisted = mark?.shortlisted ?? false
                let passed = mark?.passed ?? false
                switch view {
                case .shortlist:
                    return shortlisted
                case .all:
                    switch filter {
                    case .everything: return true
                    case .left: return !shortlisted && !passed
                    case .passed: return passed && !shortlisted
                    }
                }
            }
        }
    }

    public static func ceremonies(db: DatabaseQueue) throws -> [String] {
        try db.read { db in
            try String.fetchAll(db, sql: "SELECT DISTINCT ceremony FROM photos WHERE hiddenDup = 0 ORDER BY ceremony")
        }
    }

    public static func loadSession(db: DatabaseQueue) throws -> SessionRecord {
        try db.read { db in
            try SessionRecord.find(db, key: 1) ?? SessionRecord()
        }
    }

    public static func saveSession(_ session: SessionRecord, db: DatabaseQueue) throws {
        try db.write { db in
            try session.update(db)
        }
    }

    public static func loadMeta(db: DatabaseQueue) throws -> ScanMetaRecord {
        try db.read { db in
            try ScanMetaRecord.find(db, key: 1) ?? ScanMetaRecord()
        }
    }
}
