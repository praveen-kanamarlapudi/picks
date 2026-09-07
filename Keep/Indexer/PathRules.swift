import Foundation

public enum MediaClass: Sendable, Equatable {
    case jpeg
    case raw
    case video
    case videoThumb
    case junk
}

public enum PathRules: Sendable {
    public static let jpegExts: Set<String> = ["jpg", "jpeg"]
    public static let rawExts: Set<String> = ["arw", "cr2", "cr3", "nef", "dng", "raf", "orf", "rw2"]
    public static let videoExts: Set<String> = ["mp4", "mov", "mxf", "mts", "m4v"]

    public static func ext(_ path: String) -> String {
        (path as NSString).pathExtension.lowercased()
    }

    public static func classify(relativePath: String) -> MediaClass {
        let parts = relativePath.split(separator: "/").map(String.init)
        let lowerParts = parts.map { $0.lowercased() }
        let filename = parts.last ?? relativePath
        if filename.hasPrefix(".") || filename == ".DS_Store" { return .junk }
        if lowerParts.contains(where: { $0 == "_duplicate_report" }) { return .junk }
        if lowerParts.contains(where: { $0 == ".keeptrash" }) { return .junk }

        let e = ext(relativePath)
        let inThumbs = lowerParts.contains(where: { $0 == "thumbnails" || $0.hasPrefix("proxies") })
        if inThumbs { return videoExts.contains(e) || jpegExts.contains(e) ? .videoThumb : .junk }
        if videoExts.contains(e) { return .video }
        if jpegExts.contains(e) { return .jpeg }
        if rawExts.contains(e) { return .raw }
        return .junk
    }

    public static func isAlternateExport(_ relativePath: String) -> Bool {
        relativePath.split(separator: "/").map { $0.lowercased() }.contains("alternate exports")
    }

    /// Folder names that are media bins, not ceremonies (`RAW/foo.ARW`).
    public static let mediaFolderNames: Set<String> = [
        "jpg", "jpeg", "jpegs", "raw", "raws"
    ]

    /// First path segment is the ceremony for nested dumps (`01 Engagement/…`).
    /// Files sitting in the dump root (or only under JPG/RAW) belong to the dump itself.
    public static func ceremony(relativePath: String, eventName: String = "") -> String {
        let parts = relativePath.split(separator: "/").map(String.init)
        let fallback = eventName.isEmpty ? "Photos" : eventName
        guard let first = parts.first else { return fallback }
        if parts.count == 1 { return fallback }
        if parts.count == 2, mediaFolderNames.contains(first.lowercased()) { return fallback }
        return first
    }

    public static func ceremonyLooksLikeFilename(_ ceremony: String) -> Bool {
        let e = ext(ceremony)
        return jpegExts.contains(e) || rawExts.contains(e)
    }

    public static func style(relativePath: String) -> String {
        let lower = relativePath.lowercased()
        if lower.contains("candid") { return "Candid" }
        if lower.contains("traditional") { return "Traditional" }
        if lower.contains("drone") { return "Drone" }
        return "Other"
    }

    /// Camera stem used as Photo ID. Strips `__dup2`, `_1`, `__ALT` suffixes.
    public static func photoID(filename: String) -> String {
        var stem = (filename as NSString).deletingPathExtension
        if let range = stem.range(of: "__", options: .caseInsensitive) {
            stem = String(stem[..<range.lowerBound])
        }
        if stem.count > 2, stem.suffix(2).lowercased() == "_1", stem.dropLast(2).last?.isNumber == true {
            stem = String(stem.dropLast(2))
        }
        return stem
    }

    /// `AKHI0355` → `AKHI`, `M3F03442` → `M3F`, `_S9A7954` → `S9A`, `_MG_6420` → `MG`
    public static func cameraPrefix(photoID: String) -> String {
        let compact = photoID.replacingOccurrences(of: "_", with: "")
        guard let regex = try? NSRegularExpression(pattern: #"^[A-Za-z]+(?:\d[A-Za-z]+)?"#) else {
            return compact
        }
        let range = NSRange(compact.startIndex..., in: compact)
        guard let match = regex.firstMatch(in: compact, range: range),
              let swift = Range(match.range, in: compact) else {
            return compact
        }
        return String(compact[swift])
    }
}
