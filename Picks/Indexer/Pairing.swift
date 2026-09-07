import Foundation

public enum Pairing: Sendable {
    public static func pair(files: [DiscoveredFile], eventName: String = "") -> [PhotoDraft] {
        var groups: [GroupKey: [DiscoveredFile]] = [:]
        for file in files {
            let kind = PathRules.classify(relativePath: file.relativePath)
            guard kind == .jpeg || kind == .raw else { continue }
            if PathRules.isAlternateExport(file.relativePath) { continue }
            let ceremony = PathRules.ceremony(relativePath: file.relativePath, eventName: eventName)
            let pid = PathRules.photoID(filename: file.filename)
            groups[GroupKey(ceremony: ceremony, photoID: pid), default: []].append(file)
        }

        return groups.keys.sorted { ($0.ceremony, $0.photoID) < ($1.ceremony, $1.photoID) }.compactMap { key in
            draft(photoID: key.photoID, ceremony: key.ceremony, files: groups[key] ?? [])
        }
    }

    private struct GroupKey: Hashable {
        var ceremony: String
        var photoID: String
    }

    private static func draft(photoID: String, ceremony: String, files: [DiscoveredFile]) -> PhotoDraft? {
        guard !files.isEmpty else { return nil }
        let ranked = files.sorted { a, b in
            let ap = preferCandid(a.relativePath)
            let bp = preferCandid(b.relativePath)
            if ap != bp { return ap }
            return a.relativePath < b.relativePath
        }

        let jpegs = ranked.filter { PathRules.classify(relativePath: $0.relativePath) == .jpeg }
        let raws = ranked.filter { PathRules.classify(relativePath: $0.relativePath) == .raw }

        let jpegPath = jpegs.first?.relativePath
        let rawPath = raws.first?.relativePath
        let kind: CanonicalKind = rawPath == nil ? .jpeg : .raw
        let canonical = kind == .raw ? rawPath! : (jpegPath ?? ranked[0].relativePath)
        let size = (kind == .raw ? raws.first?.size : jpegs.first?.size) ?? ranked[0].size
        let style = PathRules.style(relativePath: canonical)
        let camera = PathRules.cameraPrefix(photoID: photoID)

        return PhotoDraft(
            photoID: photoID,
            ceremony: ceremony,
            style: style,
            camera: camera,
            canonicalPath: canonical,
            canonicalKind: kind,
            jpegPath: jpegPath,
            rawPath: rawPath,
            hiddenDup: false,
            fileSize: size
        )
    }

    private static func preferCandid(_ path: String) -> Bool {
        path.lowercased().contains("candid")
    }
}
