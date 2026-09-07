import CryptoKit
import Foundation

public enum SupportPaths: Sendable {
    public static func applicationSupportRoot() throws -> URL {
        let fm = FileManager.default
        // Sandboxed builds stored catalogs in the container. Keep using that
        // folder so marks survive turning the sandbox off (needed for Drive deletes).
        let container = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Containers/app.keep.mac/Data/Library/Application Support/Keep")
        if fm.fileExists(atPath: container.path) {
            return container
        }
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Keep", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func eventID(for root: URL) -> String {
        let path = root.standardizedFileURL.resolvingSymlinksInPath().path
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    public static func eventDirectory(id: String) throws -> URL {
        let dir = try applicationSupportRoot().appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("thumbs", isDirectory: true), withIntermediateDirectories: true)
        return dir
    }

    public static func databaseURL(eventID: String) throws -> URL {
        try eventDirectory(id: eventID).appendingPathComponent("catalog.sqlite")
    }

    public static func bookmarkURL(eventID: String) throws -> URL {
        try eventDirectory(id: eventID).appendingPathComponent("folder.bookmark")
    }

    public static func thumbsDirectory(eventID: String) throws -> URL {
        try eventDirectory(id: eventID).appendingPathComponent("thumbs", isDirectory: true)
    }
}
