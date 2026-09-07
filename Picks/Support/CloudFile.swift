import Foundation

public enum CloudFileState: Sendable, Equatable {
    case local
    case downloading
    case remote
    case missing
}

public enum CloudFile: Sendable {
    public static func state(of url: URL) -> CloudFileState {
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            return .missing
        }
        let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ])
        guard values?.isUbiquitousItem == true else { return .local }
        if values?.ubiquitousItemDownloadingStatus == .current {
            return .local
        }
        if values?.ubiquitousItemDownloadingStatus == .downloaded {
            return .local
        }
        return .remote
    }

    /// Hydrate this file only. Never walk the dump.
    @discardableResult
    public static func requestDownload(_ url: URL) -> CloudFileState {
        let current = state(of: url)
        if current == .missing { return .missing }
        if current == .local { return .local }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        return .downloading
    }
}
