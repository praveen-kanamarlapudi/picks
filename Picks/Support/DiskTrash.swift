import Foundation
import GRDB

public enum DiskTrashError: Error, LocalizedError, Sendable {
    case noFiles
    case missingInTrash(String)

    public var errorDescription: String? {
        switch self {
        case .noFiles:
            return "That photo’s files are already gone from disk."
        case .missingInTrash(let name):
            return "Can’t undo \(name) — it is no longer in Trash. Empty Trash cannot be reversed."
        }
    }
}

public struct DiskDeleteUndo: Sendable {
    public var photo: PhotoRecord
    public var mark: MarkRecord?
    public var files: [URL: URL]

    public init(photo: PhotoRecord, mark: MarkRecord?, files: [URL: URL]) {
        self.photo = photo
        self.mark = mark
        self.files = files
    }
}

/// Moves a photo’s files (RAW + JPEG) to macOS Trash and can put them back.
/// Drive files go in the Drive volume trash (`GoogleDrive-…/.Trash`), which Finder shows.
public enum DiskTrash: Sendable {
    /// Leftover hidden folders from older builds. Still ignored by the indexer.
    public static let dumpTrashFolder = ".PicksTrash"
    public static let legacyDumpTrashFolder = ".KeepTrash"

    public static func urls(for photo: PhotoRecord, root: URL) -> [URL] {
        var seen = Set<String>()
        var urls: [URL] = []
        for rel in [photo.rawPath, photo.jpegPath, photo.canonicalPath] {
            guard let rel, !rel.isEmpty else { continue }
            let url = PhotoRecord.canonicalURL(root: root, relative: rel).standardizedFileURL
            if seen.insert(url.path).inserted {
                urls.append(url)
            }
        }
        return urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public static func trash(_ urls: [URL], dumpRoot: URL) async throws -> [URL: URL] {
        _ = dumpRoot
        guard !urls.isEmpty else { throw DiskTrashError.noFiles }
        var map: [URL: URL] = [:]
        var moved: [URL: URL] = [:]
        do {
            for url in urls {
                let dest = try trashOne(url)
                map[url] = dest
                moved[url] = dest
            }
        } catch {
            try? restore(moved)
            throw error
        }
        return map
    }

    private static func trashOne(_ url: URL) throws -> URL {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        var resulting: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
            if let trashed = resulting as URL? { return trashed }
            if !FileManager.default.fileExists(atPath: url.path) { return url }
        } catch {
            // File Provider sometimes rejects trashItem. Same-volume Trash still works.
        }
        return try moveToVolumeTrash(url)
    }

    /// Finder Trash for that volume (`~/.Trash` locally, `GoogleDrive-…/.Trash` on Drive).
    public static func moveToVolumeTrash(_ url: URL) throws -> URL {
        let trashDir = try FileManager.default.url(
            for: .trashDirectory,
            in: .userDomainMask,
            appropriateFor: url,
            create: true
        )
        let dest = uniqueDestination(in: trashDir, for: url)
        do {
            try FileManager.default.moveItem(at: url, to: dest)
            return dest
        } catch {
            try FileManager.default.copyItem(at: url, to: dest)
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                try? FileManager.default.removeItem(at: dest)
                throw error
            }
            return dest
        }
    }

    public static func restore(_ map: [URL: URL]) throws {
        for (original, trashed) in map {
            if FileManager.default.fileExists(atPath: original.path) { continue }
            guard FileManager.default.fileExists(atPath: trashed.path) else {
                throw DiskTrashError.missingInTrash(original.lastPathComponent)
            }
            let parent = original.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parent.path) {
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            }
            try FileManager.default.moveItem(at: trashed, to: original)
        }
    }

    public static func insertPreservingID(_ photo: PhotoRecord, db: Database) throws {
        guard let id = photo.id else {
            var row = photo
            try row.insert(db)
            return
        }
        try db.execute(
            sql: """
                INSERT INTO photos (
                    id, photoID, ceremony, style, camera, canonicalPath, canonicalKind,
                    jpegPath, rawPath, hiddenDup, fileSize
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                id, photo.photoID, photo.ceremony, photo.style, photo.camera,
                photo.canonicalPath, photo.canonicalKind, photo.jpegPath, photo.rawPath,
                photo.hiddenDup, photo.fileSize
            ]
        )
    }

    private static func uniqueDestination(in directory: URL, for url: URL) -> URL {
        var dest = directory.appendingPathComponent(url.lastPathComponent)
        guard FileManager.default.fileExists(atPath: dest.path) else { return dest }
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var i = 1
        repeat {
            let name = ext.isEmpty ? "\(stem) (\(i))" : "\(stem) (\(i)).\(ext)"
            dest = directory.appendingPathComponent(name)
            i += 1
        } while FileManager.default.fileExists(atPath: dest.path)
        return dest
    }
}
