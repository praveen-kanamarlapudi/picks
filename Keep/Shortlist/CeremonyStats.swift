import Foundation
import GRDB

public struct CeremonyStats: Sendable, Identifiable, Equatable {
    public var id: String { "\(ceremony)|\(style)" }
    public var ceremony: String
    public var style: String
    public var stills: Int
    public var shortlisted: Int
    public var passed: Int
    public var coverPath: String?

    public var left: Int { max(0, stills - shortlisted - passed) }
    public var reviewed: Int { shortlisted + passed }
    public var progress: Double {
        guard stills > 0 else { return 0 }
        return Double(reviewed) / Double(stills)
    }

    public var displayName: String {
        if let range = ceremony.range(of: #"^\d+\s+"#, options: .regularExpression) {
            return String(ceremony[range.upperBound...])
        }
        return ceremony
    }

    public var title: String {
        style.isEmpty || style == "Other" ? ceremony : "\(ceremony)  ·  \(style)"
    }
}

public extension PhotoQuery {
    static func ceremonyStats(db: DatabaseQueue) throws -> [CeremonyStats] {
        try db.read { db in
            let photos = try PhotoRecord
                .filter(Column("hiddenDup") == false)
                .order(Column("ceremony"), Column("photoID"))
                .fetchAll(db)
            let marks = Dictionary(uniqueKeysWithValues: try MarkRecord.fetchAll(db).map { ($0.photoPk, $0) })

            struct Key: Hashable { var ceremony: String; var style: String }
            var stills: [Key: Int] = [:]
            var short: [Key: Int] = [:]
            var passed: [Key: Int] = [:]
            var cover: [Key: String] = [:]

            for photo in photos {
                let key = Key(ceremony: photo.ceremony, style: photo.style)
                stills[key, default: 0] += 1
                if cover[key] == nil {
                    cover[key] = photo.canonicalPath
                }
                guard let pk = photo.id, let mark = marks[pk] else { continue }
                if mark.shortlisted { short[key, default: 0] += 1 }
                else if mark.passed { passed[key, default: 0] += 1 }
            }

            return stills.keys.sorted {
                if $0.ceremony != $1.ceremony { return $0.ceremony < $1.ceremony }
                return StylePreference.styleRank($0.style) < StylePreference.styleRank($1.style)
            }.map { key in
                CeremonyStats(
                    ceremony: key.ceremony,
                    style: key.style,
                    stills: stills[key] ?? 0,
                    shortlisted: short[key] ?? 0,
                    passed: passed[key] ?? 0,
                    coverPath: cover[key]
                )
            }
        }
    }

    static func shortlist(
        db: Database,
        ceremony: String? = nil,
        style: String? = nil
    ) throws -> [PhotoRecord] {
        let marks = try MarkRecord.filter(Column("shortlisted") == true).fetchAll(db)
        let ids = marks.map(\.photoPk)
        guard !ids.isEmpty else { return [] }
        var request = PhotoRecord
            .filter(ids.contains(Column("id")))
            .filter(Column("hiddenDup") == false)
        if let ceremony, !ceremony.isEmpty {
            request = request.filter(Column("ceremony") == ceremony)
        }
        if let style, !style.isEmpty {
            request = request.filter(Column("style") == style)
        }
        return try request.order(Column("ceremony"), Column("photoID")).fetchAll(db)
    }

    static func shortlist(
        db queue: DatabaseQueue,
        ceremony: String? = nil,
        style: String? = nil
    ) throws -> [PhotoRecord] {
        try queue.read { try shortlist(db: $0, ceremony: ceremony, style: style) }
    }

    static func styles(db: DatabaseQueue, ceremony: String) throws -> [String] {
        try db.read { db in
            StylePreference.sortedStyles(
                try String.fetchAll(
                    db,
                    sql: "SELECT DISTINCT style FROM photos WHERE hiddenDup = 0 AND ceremony = ?",
                    arguments: [ceremony]
                )
            )
        }
    }

    static func stillCount(db: DatabaseQueue, ceremony: String, style: String) throws -> Int {
        try db.read { db in
            var request = PhotoRecord
                .filter(Column("ceremony") == ceremony)
                .filter(Column("hiddenDup") == false)
            if !style.isEmpty {
                request = request.filter(Column("style") == style)
            }
            return try request.fetchCount(db)
        }
    }
}
