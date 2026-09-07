import AppKit
import Foundation
import GRDB
import KeepCore
import Observation

enum Route: Equatable {
    case open
    case scan
    case home
    case review
}

@MainActor
@Observable
final class AppModel {
    var route: Route = .open
    var recents: [RecentEvent] = RecentsStore.load()
    var scanStats = ScanStats()
    var scanMessage = "Scanning…"
    var errorText: String?

    var eventID: String?
    var eventName: String = ""
    var rootURL: URL?
    var accessing = false

    var db: DatabaseQueue?
    var markStore: MarkStore?

    var ceremonies: [String] = []
    var ceremony: String = ""
    /// Empty = every style in the ceremony (Candid + Traditional).
    var styleFilter: String = ""
    var stylesInCeremony: [String] = []
    var viewMode: ReviewViewMode = .all
    var filter: AllFilter = .left
    var photos: [PhotoRecord] = []
    var index: Int = 0
    var marks: [Int64: MarkRecord] = [:]

    var current: PhotoRecord? {
        guard photos.indices.contains(index) else { return nil }
        return photos[index]
    }

    var shortlistCount: Int {
        marks.values.filter(\.shortlisted).count
    }

    var passedCount: Int {
        marks.values.filter { $0.passed && !$0.shortlisted }.count
    }

    var leftCount: Int {
        photos.count
    }

    var ceremonyAllCount: Int = 0
    var ceremonyCards: [CeremonyStats] = []
    var showingExport = false
    var exportCopied = false
    var cloudState: CloudFileState = .local
    var showGrid = false
    var toast = ""

    private enum EditUndo {
        case mark(MarkSnapshot)
        case diskDelete(DiskDeleteUndo)
    }

    private var undos: [EditUndo] = []
    private var toastToken = 0
    private var deleting = false

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open dump"
        panel.message = "Choose a photo dump. RAW is the photo when it exists."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await open(url: url, rescan: true) }
    }

    func openRecent(_ item: RecentEvent) {
        Task {
            do {
                let url = try EventBookmark.resolve(eventID: item.id)
                await open(url: url, eventIDHint: item.id, rescan: false)
            } catch {
                errorText = "Could not reopen \(item.name). Choose the folder again."
            }
        }
    }

    func open(url: URL, eventIDHint: String? = nil, rescan: Bool) async {
        errorText = nil
        stopAccess()
        accessing = url.startAccessingSecurityScopedResource()
        let id = eventIDHint ?? SupportPaths.eventID(for: url)
        eventID = id
        eventName = url.lastPathComponent
        rootURL = url
        Thumbnailer.clearMemory()

        do {
            try EventBookmark.save(root: url, eventID: id)
            RecentsStore.remember(id: id, name: eventName)
            recents = RecentsStore.load()

            let queue = try Catalog.openEvent(id: id)
            db = queue
            markStore = MarkStore(db: queue)

            let existing = try await queue.read { db in
                try PhotoRecord.fetchCount(db)
            }

            if rescan || existing == 0 {
                route = .scan
                scanMessage = "Walking files…"
                let stats = try await Task.detached {
                    try Indexer.scan(root: url, db: queue)
                }.value
                scanStats = stats
            } else {
                try Indexer.collapseMisindexedFlatDump(db: queue, eventName: eventName)
                scanStats = try await Task.detached {
                    let meta = try PhotoQuery.loadMeta(db: queue)
                    var s = ScanStats()
                    s.stills = meta.stills
                    s.canonicalRaw = meta.canonicalRaw
                    s.jpegOnly = meta.jpegOnly
                    s.dupsHidden = meta.dupsHidden
                    s.videoThumbsSkipped = meta.videoThumbsSkipped
                    s.videosIgnored = meta.videosIgnored
                    return s
                }.value
            }

            undos = []
            try loadWorkspace()
            route = (rescan || existing == 0) ? .home : .review
        } catch {
            errorText = error.localizedDescription
            route = .open
            stopAccess()
        }
    }

    func loadWorkspace() throws {
        guard let db else { return }
        ceremonies = try PhotoQuery.ceremonies(db: db)
        let session = try PhotoQuery.loadSession(db: db)
        ceremony = StylePreference.defaultCeremony(session: session.ceremony, all: ceremonies)
        viewMode = ReviewViewMode(rawValue: session.view) ?? .all
        filter = AllFilter(rawValue: session.filter) ?? .left
        let styles = (try? PhotoQuery.styles(db: db, ceremony: ceremony)) ?? []
        if styles.contains(session.styleFilter), !StylePreference.isCandid(session.styleFilter) {
            styleFilter = session.styleFilter
        } else {
            styleFilter = StylePreference.defaultStyle(in: styles)
        }
        marks = try markStore?.marksByPhoto() ?? [:]
        try reloadPhotos(restorePk: session.lastPhotoPk)
        refreshHome()
        refreshCloud()
    }

    func reloadPhotos(restorePk: Int64? = nil) throws {
        guard let db else { return }
        let keepID = restorePk ?? current?.id
        stylesInCeremony = try PhotoQuery.styles(db: db, ceremony: ceremony)
        if !styleFilter.isEmpty, !stylesInCeremony.contains(styleFilter) {
            styleFilter = StylePreference.defaultStyle(in: stylesInCeremony)
        }
        photos = try PhotoQuery.visiblePhotos(
            db: db,
            ceremony: ceremony,
            style: styleFilter,
            view: viewMode,
            filter: filter
        )
        ceremonyAllCount = try PhotoQuery.stillCount(db: db, ceremony: ceremony, style: styleFilter)
        if let keepID, let i = photos.firstIndex(where: { $0.id == keepID }) {
            index = i
        } else if !photos.isEmpty {
            index = min(index, photos.count - 1)
        } else {
            index = 0
        }
        persistSession()
        refreshHome()
        refreshCloud()
    }

    func setCeremony(_ name: String) {
        ceremony = name
        let styles = db.flatMap { try? PhotoQuery.styles(db: $0, ceremony: name) } ?? []
        styleFilter = StylePreference.defaultStyle(in: styles)
        try? reloadPhotos()
    }

    func setStyle(_ style: String) {
        styleFilter = style
        try? reloadPhotos()
    }

    func setView(_ mode: ReviewViewMode) {
        viewMode = mode
        try? reloadPhotos()
    }

    func setFilter(_ f: AllFilter) {
        filter = f
        try? reloadPhotos()
    }

    func go(_ delta: Int) {
        guard !photos.isEmpty else { return }
        index = min(max(0, index + delta), photos.count - 1)
        persistSession()
        refreshCloud()
    }

    func space() {
        guard let photo = current, let pk = photo.id, let store = markStore else { return }
        do {
            let snap = try store.snapshot(pk)
            pushUndo(.mark(snap))
            if viewMode == .shortlist || snap.shortlisted {
                try store.apply(photoPk: pk, shortlisted: false, passed: nil)
            } else {
                try store.apply(photoPk: pk, shortlisted: true, passed: false)
            }
            marks = try store.marksByPhoto()
            try reloadPhotos(restorePk: pk)
            advanceIfStillVisible(pk)
        } catch {
            errorText = error.localizedDescription
        }
    }

    func pass() {
        guard let photo = current, let pk = photo.id, let store = markStore else { return }
        do {
            let snap = try store.snapshot(pk)
            pushUndo(.mark(snap))
            if viewMode == .shortlist {
                try store.apply(photoPk: pk, shortlisted: false, passed: nil)
            } else {
                try store.apply(photoPk: pk, shortlisted: false, passed: true)
            }
            marks = try store.marksByPhoto()
            try reloadPhotos(restorePk: pk)
            // photo usually leaves "left" / shortlist; same index is the next one
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func advanceIfStillVisible(_ pk: Int64) {
        if let i = photos.firstIndex(where: { $0.id == pk }) {
            index = min(i + 1, photos.count - 1)
            persistSession()
        }
    }

    func unmark() {
        guard let photo = current, let pk = photo.id, let store = markStore else { return }
        do {
            pushUndo(.mark(try store.snapshot(pk)))
            try store.apply(photoPk: pk, shortlisted: false, passed: false)
            marks = try store.marksByPhoto()
            try reloadPhotos(restorePk: pk)
        } catch {
            errorText = error.localizedDescription
        }
    }

    func undo() {
        guard let item = undos.popLast() else { return }
        do {
            switch item {
            case .mark(let snap):
                guard let store = markStore else { return }
                _ = try store.apply(
                    photoPk: snap.photoPk,
                    shortlisted: snap.shortlisted,
                    passed: snap.passed,
                    pushUndo: false
                )
                marks = try store.marksByPhoto()
                try reloadPhotos(restorePk: snap.photoPk)
            case .diskDelete(let deleted):
                try restoreDeleted(deleted)
            }
        } catch {
            undos.append(item)
            errorText = error.localizedDescription
        }
    }

    func deleteCurrent() {
        guard !deleting else { return }
        deleting = true
        Task { @MainActor in
            await deleteCurrentAsync(didPrompt: false)
            deleting = false
        }
    }

    private func deleteCurrentAsync(didPrompt: Bool) async {
        guard let photo = current, let root = rootURL, let db else { return }
        let urls = DiskTrash.urls(for: photo, root: root)
        do {
            let trashed = try await DiskTrash.trash(urls, dumpRoot: root)
            let mark = photo.id.flatMap { marks[$0] }
            try await db.write { db in
                if let pk = photo.id {
                    _ = try MarkRecord.deleteOne(db, key: pk)
                    _ = try PhotoRecord.deleteOne(db, key: pk)
                }
            }
            pushUndo(.diskDelete(DiskDeleteUndo(photo: photo, mark: mark, files: trashed)))
            scanStats.stills = max(0, scanStats.stills - 1)
            marks = (try? markStore?.marksByPhoto()) ?? [:]
            try reloadPhotos()
            if DiskTrash.usedKeepTrash(trashed) {
                showToast("\(photo.photoID) removed  ·  ⌘Z to undo")
            } else {
                showToast("\(photo.photoID) → Trash  ·  ⌘Z to undo")
            }
        } catch {
            if !didPrompt, await askForWriteAccess(dump: root) {
                await deleteCurrentAsync(didPrompt: true)
                return
            }
            let text = error.localizedDescription
            if text.localizedCaseInsensitiveContains("permission") {
                errorText = "Couldn’t delete \(photo.photoID). Choose the dump folder again (write access), or delete it once in Finder."
            } else {
                errorText = text
            }
        }
    }

    /// Old bookmarks were created read-only. Re-selecting the dump grants write.
    private func askForWriteAccess(dump: URL) async -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Allow"
        panel.directoryURL = dump
        panel.message = "Keep needs write access to delete photos. Select this same dump folder."
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        stopAccess()
        accessing = url.startAccessingSecurityScopedResource()
        rootURL = url
        if let eventID {
            try? EventBookmark.save(root: url, eventID: eventID)
        }
        return accessing
    }

    private func restoreDeleted(_ deleted: DiskDeleteUndo) throws {
        guard let db else { return }
        try DiskTrash.restore(deleted.files)
        try db.write { db in
            try DiskTrash.insertPreservingID(deleted.photo, db: db)
            if let mark = deleted.mark {
                try mark.insert(db)
            }
        }
        scanStats.stills += 1
        marks = (try? markStore?.marksByPhoto()) ?? [:]
        try reloadPhotos(restorePk: deleted.photo.id)
        showToast("Restored \(deleted.photo.photoID)")
    }

    private func pushUndo(_ item: EditUndo) {
        undos.append(item)
        if undos.count > 80 { undos.removeFirst(undos.count - 80) }
    }

    private func showToast(_ text: String) {
        toast = text
        toastToken += 1
        let token = toastToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if toastToken == token { toast = "" }
        }
    }

    func isShortlisted(_ photo: PhotoRecord) -> Bool {
        guard let pk = photo.id else { return false }
        return marks[pk]?.shortlisted ?? false
    }

    func note(for photo: PhotoRecord) -> String {
        guard let pk = photo.id else { return "" }
        return marks[pk]?.note ?? ""
    }

    func setNote(_ text: String, on photo: PhotoRecord) {
        guard let pk = photo.id, let store = markStore else { return }
        do {
            _ = try store.setNote(photoPk: pk, text)
            marks = try store.marksByPhoto()
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Jump to a camera ID. Matches the current ceremony first, then the rest of the dump.
    @discardableResult
    func jump(to query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, let db else { return false }
        do {
            let all = try db.read { db in
                try PhotoRecord
                    .filter(Column("hiddenDup") == false)
                    .order(Column("ceremony"), Column("photoID"))
                    .fetchAll(db)
            }
            let lower = needle.lowercased()
            let ranked = all.filter { $0.photoID.lowercased().contains(lower) }
            let match =
                ranked.first(where: { $0.ceremony == ceremony && $0.photoID.compare(needle, options: .caseInsensitive) == .orderedSame })
                ?? ranked.first(where: { $0.photoID.compare(needle, options: .caseInsensitive) == .orderedSame })
                ?? ranked.first(where: { $0.ceremony == ceremony })
                ?? ranked.first
            guard let match else { return false }

            if viewMode == .shortlist, !isShortlisted(match) {
                viewMode = .all
            }
            filter = .everything
            ceremony = match.ceremony
            try reloadPhotos(restorePk: match.id)
            return true
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }

    func canonicalURL(for photo: PhotoRecord) -> URL? {
        guard let rootURL else { return nil }
        return PhotoRecord.canonicalURL(root: rootURL, relative: photo.canonicalPath)
    }

    var thumbCacheDir: URL? {
        guard let eventID else { return nil }
        return try? SupportPaths.thumbsDirectory(eventID: eventID)
    }

    var ceremonyShortlistCount: Int {
        ceremonyCards
            .filter { $0.ceremony == ceremony && (styleFilter.isEmpty || $0.style == styleFilter) }
            .reduce(0) { $0 + $1.shortlisted }
    }

    var totalShortlisted: Int {
        ceremonyCards.reduce(0) { $0 + $1.shortlisted }
    }

    func refreshHome() {
        guard let db else { return }
        ceremonyCards = (try? PhotoQuery.ceremonyStats(db: db)) ?? []
    }

    func goHome() {
        persistSession()
        showGrid = false
        refreshHome()
        route = .home
    }

    func openCeremony(_ name: String) {
        let styles = db.flatMap { try? PhotoQuery.styles(db: $0, ceremony: name) } ?? []
        openPile(ceremony: name, style: StylePreference.defaultStyle(in: styles))
    }

    func openPile(ceremony name: String, style: String) {
        ceremony = name
        styleFilter = style
        viewMode = .all
        filter = .left
        showGrid = false
        route = .review
        try? reloadPhotos()
    }

    func continueCeremony(_ name: String) {
        openPile(ceremony: name, style: styleFilter)
    }

    func toggleGrid() {
        showGrid.toggle()
    }

    func selectPhoto(_ photo: PhotoRecord) {
        if let i = photos.firstIndex(where: { $0.id == photo.id }) {
            index = i
            persistSession()
            refreshCloud()
        }
    }

    func refreshCloud() {
        guard let photo = current, let url = canonicalURL(for: photo) else {
            cloudState = .missing
            return
        }
        let state = CloudFile.state(of: url)
        if state == .remote {
            cloudState = CloudFile.requestDownload(url)
        } else {
            cloudState = state
        }
    }

    func exportRows() -> [ExportRow] {
        guard let db else { return [] }
        return (try? Exporter.rows(
            db: db,
            eventName: eventName,
            ceremony: ceremony,
            style: styleFilter.isEmpty ? nil : styleFilter
        )) ?? []
    }

    var exportScopeLabel: String {
        if styleFilter.isEmpty { return ceremony }
        return "\(ceremony) · \(styleFilter)"
    }

    func copyExportIDs() {
        Exporter.copyIDs(exportRows())
        exportCopied = true
    }

    func saveExport() {
        let rows = exportRows()
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Save export"
        panel.message = "Choose a folder for photo-ids.txt and shortlist.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dest = url.appendingPathComponent("Keep-shortlist-\(stamp)", isDirectory: true)
        do {
            try Exporter.write(rows: rows, to: dest)
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } catch {
            errorText = error.localizedDescription
        }
    }

    func persistSession() {
        guard let db else { return }
        var session = SessionRecord(
            lastPhotoPk: current?.id,
            view: viewMode.rawValue,
            filter: filter.rawValue,
            ceremony: ceremony,
            styleFilter: styleFilter
        )
        try? PhotoQuery.saveSession(session, db: db)
    }

    func backToOpen() {
        persistSession()
        stopAccess()
        route = .open
        db = nil
        markStore = nil
        photos = []
        undos = []
        toast = ""
    }

    private func stopAccess() {
        if accessing {
            rootURL?.stopAccessingSecurityScopedResource()
            accessing = false
        }
    }
}
