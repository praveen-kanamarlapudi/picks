import Foundation

public enum EventBookmarkError: Error, Sendable {
    case missing
    case stale
}

public enum EventBookmark: Sendable {
    public static func save(root: URL, eventID: String) throws {
        let data = try bookmarkData(for: root)
        try data.write(to: SupportPaths.bookmarkURL(eventID: eventID), options: .atomic)
    }

    /// Returns the resolved URL. Caller must `stopAccessingSecurityScopedResource()` when finished with the session.
    public static func resolve(eventID: String) throws -> URL {
        let url = try SupportPaths.bookmarkURL(eventID: eventID)
        guard FileManager.default.fileExists(atPath: url.path) else { throw EventBookmarkError.missing }
        let data = try Data(contentsOf: url)
        var stale = false
        let resolved = try resolveBookmarkData(data, stale: &stale)
        guard FileManager.default.fileExists(atPath: resolved.path) else { throw EventBookmarkError.stale }
        if stale {
            try save(root: resolved, eventID: eventID)
        }
        return resolved
    }

    /// Security-scoped bookmarks from the old sandboxed Keep build do not resolve
    /// with `.withSecurityScope` in unsandboxed Picks (NSCocoaErrorDomain 259).
    /// Try scoped first, then a plain bookmark — macOS still follows moved folders.
    static func resolveBookmarkData(_ data: Data, stale: inout Bool) throws -> URL {
        do {
            return try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        } catch {
            return try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        }
    }

    private static func bookmarkData(for root: URL) throws -> Data {
        let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        let options: URL.BookmarkCreationOptions = sandboxed ? [.withSecurityScope] : []
        return try root.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}
