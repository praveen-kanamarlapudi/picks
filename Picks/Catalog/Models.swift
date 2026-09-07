import Foundation
import GRDB

public enum CanonicalKind: String, Codable, Sendable {
    case raw
    case jpeg
}

public struct PhotoRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "photos"

    public var id: Int64?
    public var photoID: String
    public var ceremony: String
    public var style: String
    public var camera: String
    public var canonicalPath: String
    public var canonicalKind: String
    public var jpegPath: String?
    public var rawPath: String?
    public var hiddenDup: Bool
    public var fileSize: Int64

    public var kind: CanonicalKind {
        CanonicalKind(rawValue: canonicalKind) ?? .jpeg
    }

    public var rowID: Int64 { id ?? 0 }

    /// Unique across dumps (row IDs restart at 1 in every catalog).
    public var tileID: String { "\(rowID)-\(photoID)-\(canonicalPath)" }

    public init(
        id: Int64? = nil,
        photoID: String,
        ceremony: String,
        style: String,
        camera: String,
        canonicalPath: String,
        canonicalKind: String,
        jpegPath: String? = nil,
        rawPath: String? = nil,
        hiddenDup: Bool = false,
        fileSize: Int64 = 0
    ) {
        self.id = id
        self.photoID = photoID
        self.ceremony = ceremony
        self.style = style
        self.camera = camera
        self.canonicalPath = canonicalPath
        self.canonicalKind = canonicalKind
        self.jpegPath = jpegPath
        self.rawPath = rawPath
        self.hiddenDup = hiddenDup
        self.fileSize = fileSize
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public static func canonicalURL(root: URL, relative: String) -> URL {
        relative.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
    }
}

public struct MarkRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Hashable {
    public static let databaseTableName = "marks"

    public var photoPk: Int64
    public var shortlisted: Bool
    public var passed: Bool
    public var note: String?
    public var updatedAt: String

    public init(
        photoPk: Int64,
        shortlisted: Bool = false,
        passed: Bool = false,
        note: String? = nil,
        updatedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.photoPk = photoPk
        self.shortlisted = shortlisted
        self.passed = passed
        self.note = note
        self.updatedAt = updatedAt
    }
}

public struct SessionRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "session"

    public var id: Int64
    public var lastPhotoPk: Int64?
    public var view: String
    public var filter: String
    public var ceremony: String
    public var styleFilter: String

    public init(
        id: Int64 = 1,
        lastPhotoPk: Int64? = nil,
        view: String = ReviewViewMode.all.rawValue,
        filter: String = AllFilter.left.rawValue,
        ceremony: String = "",
        styleFilter: String = ""
    ) {
        self.id = id
        self.lastPhotoPk = lastPhotoPk
        self.view = view
        self.filter = filter
        self.ceremony = ceremony
        self.styleFilter = styleFilter
    }
}

public struct ScanMetaRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "scan_meta"

    public var id: Int64
    public var stills: Int
    public var canonicalRaw: Int
    public var jpegOnly: Int
    public var dupsHidden: Int
    public var videoThumbsSkipped: Int
    public var videosIgnored: Int
    public var lastIndexedAt: String

    public init(
        id: Int64 = 1,
        stills: Int = 0,
        canonicalRaw: Int = 0,
        jpegOnly: Int = 0,
        dupsHidden: Int = 0,
        videoThumbsSkipped: Int = 0,
        videosIgnored: Int = 0,
        lastIndexedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.stills = stills
        self.canonicalRaw = canonicalRaw
        self.jpegOnly = jpegOnly
        self.dupsHidden = dupsHidden
        self.videoThumbsSkipped = videoThumbsSkipped
        self.videosIgnored = videosIgnored
        self.lastIndexedAt = lastIndexedAt
    }
}

public enum ReviewViewMode: String, Sendable, CaseIterable {
    case all
    case shortlist
}

public enum AllFilter: String, Sendable, CaseIterable {
    case everything
    case left
    case passed
}

public struct ScanStats: Sendable, Equatable {
    public var stills: Int = 0
    public var canonicalRaw: Int = 0
    public var jpegOnly: Int = 0
    public var dupsHidden: Int = 0
    public var videoThumbsSkipped: Int = 0
    public var videosIgnored: Int = 0
    public var otherSkipped: Int = 0

    public init() {}
}

public struct PhotoDraft: Sendable, Equatable {
    public var photoID: String
    public var ceremony: String
    public var style: String
    public var camera: String
    public var canonicalPath: String
    public var canonicalKind: CanonicalKind
    public var jpegPath: String?
    public var rawPath: String?
    public var hiddenDup: Bool
    public var fileSize: Int64

    public init(
        photoID: String,
        ceremony: String,
        style: String,
        camera: String,
        canonicalPath: String,
        canonicalKind: CanonicalKind,
        jpegPath: String? = nil,
        rawPath: String? = nil,
        hiddenDup: Bool = false,
        fileSize: Int64 = 0
    ) {
        self.photoID = photoID
        self.ceremony = ceremony
        self.style = style
        self.camera = camera
        self.canonicalPath = canonicalPath
        self.canonicalKind = canonicalKind
        self.jpegPath = jpegPath
        self.rawPath = rawPath
        self.hiddenDup = hiddenDup
        self.fileSize = fileSize
    }
}

public struct DiscoveredFile: Sendable, Equatable {
    public var relativePath: String
    public var ext: String
    public var size: Int64

    public init(relativePath: String, ext: String, size: Int64) {
        self.relativePath = relativePath
        self.ext = ext
        self.size = size
    }

    public var filename: String {
        (relativePath as NSString).lastPathComponent
    }
}
