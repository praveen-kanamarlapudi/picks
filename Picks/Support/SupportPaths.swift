import CryptoKit
import Foundation

public enum SupportPaths: Sendable {
    public static func applicationSupportRoot() throws -> URL {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support")

        let picksSupport = appSupport.appendingPathComponent("Picks", isDirectory: true)
        let picksContainer = home.appendingPathComponent(
            "Library/Containers/app.picks.mac/Data/Library/Application Support/Picks"
        )
        // Pre-rename catalogs. Prefer an existing folder so shortlists survive the rebrand.
        let keepContainer = home.appendingPathComponent(
            "Library/Containers/app.keep.mac/Data/Library/Application Support/Keep"
        )
        let keepSupport = home.appendingPathComponent("Library/Application Support/Keep")

        for dir in [picksContainer, picksSupport, keepContainer, keepSupport] {
            if fm.fileExists(atPath: dir.path) {
                return dir
            }
        }
        try fm.createDirectory(at: picksSupport, withIntermediateDirectories: true)
        return picksSupport
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
