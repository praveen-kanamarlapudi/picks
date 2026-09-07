import AppKit
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

/// Moves a photo’s files (RAW + JPEG) to Trash and can put them back.
/// Google Drive / File Provider often rejects macOS Trash; then we rename into
/// `dump/.PicksTrash/` on the same volume (undo is a rename back).
public enum DiskTrash: Sendable {
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
        guard !urls.isEmpty else { throw DiskTrashError.noFiles }
        var remaining = urls
        var map: [URL: URL] = [:]

        if let recycled = await recycleViaFinder(remaining) {
            map.merge(recycled) { _, new in new }
            remaining = remaining.filter { url in
                FileManager.default.fileExists(atPath: url.path)
            }
        }

        var moved: [URL: URL] = map
        do {
            for url in remaining {
                let dest = try trashOne(url, dumpRoot: dumpRoot)
                map[url] = dest
                moved[url] = dest
            }
        } catch {
            try? restore(moved)
            throw error
        }
        return map
    }

    public static func usedDumpTrash(_ map: [URL: URL]) -> Bool {
        map.values.contains { dest in
            dest.pathComponents.contains(dumpTrashFolder)
                || dest.pathComponents.contains(legacyDumpTrashFolder)
        }
    }

    /// Finder/LaunchServices trash — this is what actually works on Google Drive.
    private static func recycleViaFinder(_ urls: [URL]) async -> [URL: URL]? {
        guard !urls.isEmpty else { return [:] }
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.recycle(urls) { mapping, error in
                if error != nil {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: mapping)
                }
            }
        }
    }

    private static func trashOne(_ url: URL, dumpRoot: URL) throws -> URL {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        var resulting: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
            if let trashed = resulting as URL? { return trashed }
            if !FileManager.default.fileExists(atPath: url.path) { return url }
        } catch {
            // Drive and File Provider reject macOS Trash. Fall through.
        }
        return try moveToDumpTrash(url, dumpRoot: dumpRoot)
    }

    public static func moveToDumpTrash(_ url: URL, dumpRoot: URL) throws -> URL {
        let rel = Indexer.relativePath(url, root: dumpRoot)
        let dest = PhotoRecord.canonicalURL(
            root: dumpRoot.appendingPathComponent(dumpTrashFolder, isDirectory: true),
            relative: rel.isEmpty ? url.lastPathComponent : rel
        )
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        do {
            try FileManager.default.moveItem(at: url, to: dest)
            return dest
        } catch {
            // Drive often can't rename; copy then delete works.
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
}
