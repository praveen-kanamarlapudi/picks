import Foundation
import GRDB

public enum Catalog {
    public static func open(at url: URL) throws -> DatabaseQueue {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let db = try DatabaseQueue(path: url.path, configuration: config)
        try migrator.migrate(db)
        return db
    }

    public static func openEvent(id: String) throws -> DatabaseQueue {
        try open(at: SupportPaths.databaseURL(eventID: id))
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "photos") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("photoID", .text).notNull()
                t.column("ceremony", .text).notNull()
                t.column("style", .text).notNull()
                t.column("camera", .text).notNull()
                t.column("canonicalPath", .text).notNull()
                t.column("canonicalKind", .text).notNull()
                t.column("jpegPath", .text)
                t.column("rawPath", .text)
                t.column("hiddenDup", .boolean).notNull().defaults(to: false)
                t.column("fileSize", .integer).notNull().defaults(to: 0)
                t.uniqueKey(["ceremony", "photoID"])
            }
            try db.create(table: "marks") { t in
                t.column("photoPk", .integer).primaryKey().references("photos", onDelete: .cascade)
                t.column("shortlisted", .boolean).notNull().defaults(to: false)
                t.column("passed", .boolean).notNull().defaults(to: false)
                t.column("note", .text)
                t.column("updatedAt", .text).notNull()
            }
            try db.create(table: "session") { t in
                t.primaryKey("id", .integer)
                t.column("lastPhotoPk", .integer)
                t.column("view", .text).notNull()
                t.column("filter", .text).notNull()
                t.column("ceremony", .text).notNull()
            }
            try db.create(table: "scan_meta") { t in
                t.primaryKey("id", .integer)
                t.column("stills", .integer).notNull()
                t.column("canonicalRaw", .integer).notNull()
                t.column("jpegOnly", .integer).notNull()
                t.column("dupsHidden", .integer).notNull()
                t.column("videoThumbsSkipped", .integer).notNull()
                t.column("videosIgnored", .integer).notNull()
                t.column("lastIndexedAt", .text).notNull()
            }
            try db.execute(sql: """
                INSERT INTO session (id, lastPhotoPk, view, filter, ceremony)
                VALUES (1, NULL, 'all', 'left', '')
                """)
            try ScanMetaRecord().insert(db)
        }
        migrator.registerMigration("v2-styleFilter") { db in
            try db.alter(table: "session") { t in
                t.add(column: "styleFilter", .text).notNull().defaults(to: "")
            }
        }
        return migrator
    }
}
