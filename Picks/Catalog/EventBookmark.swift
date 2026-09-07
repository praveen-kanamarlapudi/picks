import Foundation

public enum EventBookmarkError: Error, Sendable {
    case missing
    case stale
}

public enum EventBookmark: Sendable {
    public static func save(root: URL, eventID: String) throws {
        let data = try root.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        try data.write(to: SupportPaths.bookmarkURL(eventID: eventID), options: .atomic)
    }

    /// Returns the resolved URL. Caller must `stopAccessingSecurityScopedResource()` when finished with the session.
    public static func resolve(eventID: String) throws -> URL {
        let url = try SupportPaths.bookmarkURL(eventID: eventID)
        guard FileManager.default.fileExists(atPath: url.path) else { throw EventBookmarkError.missing }
        let data = try Data(contentsOf: url)
        var stale = false
        let resolved = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        if stale {
            try save(root: resolved, eventID: eventID)
        }
        return resolved
    }
}
