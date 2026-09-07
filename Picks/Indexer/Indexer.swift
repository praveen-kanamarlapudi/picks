import Foundation
import GRDB

public enum IndexerError: Error, Sendable {
    case notADirectory
}

public enum Indexer: Sendable {
    public static func discover(root: URL) throws -> (files: [DiscoveredFile], stats: ScanStats) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw IndexerError.notADirectory
        }

        var files: [DiscoveredFile] = []
        var stats = ScanStats()
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ([], stats)
        }

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isDirectoryKey])
            if values?.isDirectory == true { continue }
            guard values?.isRegularFile == true else { continue }
            let relative = relativePath(url, root: root)
            switch PathRules.classify(relativePath: relative) {
            case .videoThumb:
                stats.videoThumbsSkipped += 1
            case .video:
                stats.videosIgnored += 1
            case .junk:
                stats.otherSkipped += 1
            case .jpeg, .raw:
                if PathRules.isAlternateExport(relative) {
                    stats.otherSkipped += 1
                    continue
                }
                let size = Int64(values?.fileSize ?? 0)
                files.append(DiscoveredFile(relativePath: relative, ext: PathRules.ext(relative), size: size))
            }
        }
        return (files, stats)
    }

    public static func scan(root: URL, db: DatabaseQueue) throws -> ScanStats {
        let (files, walkStats) = try discover(root: root)
        var drafts = Pairing.pair(files: files, eventName: root.lastPathComponent)
        let dupPaths = DuplicateIngest.dupPaths(eventRoot: root)

        if !dupPaths.isEmpty {
            drafts = drafts.map { draft in
                var next = draft
                let canonIsDup = dupPaths.contains(draft.canonicalPath)
                let hasLiveSidecar =
                    (draft.rawPath.map { !dupPaths.contains($0) } ?? false)
                    || (draft.jpegPath.map { !dupPaths.contains($0) } ?? false)
                if canonIsDup && hasLiveSidecar {
                    if let raw = draft.rawPath, !dupPaths.contains(raw) {
                        next.canonicalPath = raw
                        next.canonicalKind = .raw
                    } else if let jpeg = draft.jpegPath, !dupPaths.contains(jpeg) {
                        next.canonicalPath = jpeg
                        next.canonicalKind = .jpeg
                    }
                }
                return next
            }
        }

        var stats = walkStats
        stats.stills = drafts.count
        stats.canonicalRaw = drafts.filter { $0.canonicalKind == .raw }.count
        stats.jpegOnly = drafts.filter { $0.canonicalKind == .jpeg }.count
        stats.dupsHidden = 0

        try db.write { db in
            struct KeptMark: Sendable {
                var photoID: String
                var ceremony: String
                var shortlisted: Bool
                var passed: Bool
                var note: String?
            }
            let kept: [KeptMark] = try {
                let photos = try PhotoRecord.fetchAll(db)
                let marks = Dictionary(uniqueKeysWithValues: try MarkRecord.fetchAll(db).map { ($0.photoPk, $0) })
                return photos.compactMap { photo -> KeptMark? in
                    guard let pk = photo.id, let mark = marks[pk] else { return nil }
                    if !mark.shortlisted, !mark.passed, (mark.note ?? "").isEmpty { return nil }
                    return KeptMark(
                        photoID: photo.photoID,
                        ceremony: photo.ceremony,
                        shortlisted: mark.shortlisted,
                        passed: mark.passed,
                        note: mark.note
                    )
                }
            }()
            let keptByKey = Dictionary(uniqueKeysWithValues: kept.map { ("\($0.ceremony)|\($0.photoID)", $0) })

            try PhotoRecord.deleteAll(db)
            try MarkRecord.deleteAll(db)
            for draft in drafts {
                var row = PhotoRecord(
                    photoID: draft.photoID,
                    ceremony: draft.ceremony,
                    style: draft.style,
                    camera: draft.camera,
                    canonicalPath: draft.canonicalPath,
                    canonicalKind: draft.canonicalKind.rawValue,
                    jpegPath: draft.jpegPath,
                    rawPath: draft.rawPath,
                    hiddenDup: draft.hiddenDup,
                    fileSize: draft.fileSize
                )
                try row.insert(db)
                if let pk = row.id, let kept = keptByKey["\(draft.ceremony)|\(draft.photoID)"] {
                    var mark = MarkRecord(
                        photoPk: pk,
                        shortlisted: kept.shortlisted,
                        passed: kept.passed,
                        note: kept.note
                    )
                    try mark.insert(db)
                }
            }
            var meta = try ScanMetaRecord.find(db, key: 1) ?? ScanMetaRecord()
            meta.stills = stats.stills
            meta.canonicalRaw = stats.canonicalRaw
            meta.jpegOnly = stats.jpegOnly
            meta.dupsHidden = stats.dupsHidden
            meta.videoThumbsSkipped = stats.videoThumbsSkipped
            meta.videosIgnored = stats.videosIgnored
            meta.lastIndexedAt = ISO8601DateFormatter().string(from: Date())
            try meta.update(db)

            var session = try SessionRecord.find(db, key: 1) ?? SessionRecord()
            if session.ceremony.isEmpty || !drafts.contains(where: { $0.ceremony == session.ceremony }) {
                session.ceremony = drafts.first?.ceremony ?? ""
                session.lastPhotoPk = nil
            }
            try session.update(db)
        }
        return stats
    }

    /// Older builds used the filename as the ceremony for flat dumps (`SAB09390.JPG`).
    /// Collapse those into one pile named after the folder. Nested dumps are untouched.
    public static func collapseMisindexedFlatDump(db: DatabaseQueue, eventName: String) throws {
        let name = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        try db.write { db in
            let photos = try PhotoRecord.fetchAll(db)
            guard !photos.isEmpty else { return }
            let broken = photos.filter { PathRules.ceremonyLooksLikeFilename($0.ceremony) }
            guard broken.count * 2 >= photos.count else { return }

            for var photo in broken {
                photo.ceremony = name
                try photo.update(db)
            }
            if var session = try SessionRecord.fetchOne(db, key: 1) {
                if PathRules.ceremonyLooksLikeFilename(session.ceremony) || session.ceremony.isEmpty {
                    session.ceremony = name
                    if PathRules.ceremonyLooksLikeFilename(session.styleFilter) {
                        session.styleFilter = ""
                    }
                    try session.update(db)
                }
            }
        }
    }

    public static func relativePath(_ url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let filePath = url.standardizedFileURL.resolvingSymlinksInPath().path
        if filePath.hasPrefix(rootPath) {
            let rest = String(filePath.dropFirst(rootPath.count))
            return rest.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return url.lastPathComponent
    }
}
