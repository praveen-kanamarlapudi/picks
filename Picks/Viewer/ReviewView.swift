import AppKit
import PicksCore
import SwiftUI

struct ReviewView: View {
    @Environment(AppModel.self) private var model
    @State private var zoom = ZoomSession()
    @State private var zoomAnchor: CGPoint = .zero
    @State private var viewport: CGSize = CGSize(width: 1200, height: 800)
    @State private var imageSize: CGSize = CGSize(width: 3, height: 2)
    @State private var monitor: Any?
    @State private var overlay: FieldOverlay = .none
    @State private var overlayText = ""
    @FocusState private var overlayFocused: Bool

    private enum FieldOverlay {
        case none
        case note
        case jump
    }

    var body: some View {
        Group {
            if model.showGrid {
                VStack(spacing: 0) {
                    chromeHeader
                    GridView()
                    if overlay != .none { overlayField.padding(.horizontal, 8).padding(.vertical, 4) }
                    keys
                        .padding(.vertical, 3)
                        .background(.regularMaterial)
                }
            } else {
                VStack(spacing: 0) {
                    chromeHeader
                    ZStack {
                        Theme.photoWell
                        PhotoCanvas(
                            url: model.current.flatMap { model.canonicalURL(for: $0) },
                            zoom: $zoom,
                            cursor: zoomAnchor
                        )
                        if model.current == nil { emptyState }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    if overlay != .none {
                        overlayField
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.regularMaterial)
                    }
                    filmstrip
                    keys
                        .padding(.vertical, 4)
                        .background(.regularMaterial)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active(let loc) = phase { zoomAnchor = loc }
        }
        .onPreferenceChange(ViewportPreference.self) { viewport = $0 == .zero ? viewport : $0 }
        .onPreferenceChange(ImageSizePreference.self) { if $0 != .zero { imageSize = $0 } }
        .onChange(of: model.current?.rowID) { _, _ in
            zoom.pan = .zero
            zoom.clamp(viewport: viewport, imageSize: imageSize)
        }
        .onAppear { installKeys() }
        .onDisappear { removeKeys() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            if model.viewMode == .shortlist {
                Text("Shortlist is empty")
                    .font(.title2)
                Text("Switch to All and press Space on a photo you want processed.")
                    .foregroundStyle(Theme.muted)
                Button("View All") { model.setView(.all) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.gold)
                    .foregroundStyle(.black)
            } else if model.filter == .left {
                Text("\(displayCeremony) is reviewed")
                    .font(.title2)
                Text("Look at the shortlist, or pick another ceremony.")
                    .foregroundStyle(Theme.muted)
            } else {
                Text("No photos in this filter")
                    .font(.title2)
                    .foregroundStyle(Theme.muted)
            }
        }
        .multilineTextAlignment(.center)
        .padding(32)
    }

    private var displayCeremony: String {
        if let range = model.ceremony.range(of: #"^\d+\s+"#, options: .regularExpression) {
            return String(model.ceremony[range.upperBound...])
        }
        return model.ceremony
    }

    private var chromeHeader: some View {
        header
            .padding(.top, 26)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button("←") { model.goHome() }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.muted)
                .help("Event home")

            Picker("", selection: Binding(get: { model.ceremony }, set: { model.setCeremony($0) })) {
                ForEach(model.ceremonies, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: 180)

            if model.stylesInCeremony.count > 1 {
                Picker("", selection: Binding(get: { model.styleFilter }, set: { model.setStyle($0) })) {
                    Text("All styles").tag("")
                    ForEach(model.stylesInCeremony, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: 130)
            }

            HStack(spacing: 0) {
                seg("All", on: model.viewMode == .all, count: model.ceremonyAllCount) {
                    model.setView(.all)
                }
                seg("Shortlist", on: model.viewMode == .shortlist, count: model.ceremonyShortlistCount) {
                    model.setView(.shortlist)
                }
            }
            .background(Theme.chrome, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))

            if model.viewMode == .all {
                HStack(spacing: 4) {
                    chip("Everything", on: model.filter == .everything) { model.setFilter(.everything) }
                    chip("Left", on: model.filter == .left) { model.setFilter(.left) }
                    chip("Passed", on: model.filter == .passed) { model.setFilter(.passed) }
                }
            }

            if let photo = model.current {
                let on = model.isShortlisted(photo)
                Button {
                    model.space()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: on ? "bookmark.fill" : "bookmark")
                        Text(on ? (model.viewMode == .shortlist ? "Remove" : "In shortlist") : "Add to shortlist")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(on ? Theme.gold : Theme.text)
                .background(on ? Theme.goldDim : Theme.chrome, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(on ? Theme.gold.opacity(0.45) : Theme.line)
                )

                Text(photo.photoID)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.text)
                if !model.note(for: photo).isEmpty {
                    Text(model.note(for: photo))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.gold)
                        .lineLimit(1)
                        .frame(maxWidth: 220, alignment: .leading)
                }
                if model.cloudState == .remote || model.cloudState == .downloading {
                    Text(model.cloudState == .downloading ? "LOADING" : "CLOUD")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.5)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.gold.opacity(0.5)))
                        .foregroundStyle(Theme.gold)
                }
                if photo.kind == .raw {
                    Text("RAW")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line))
                        .foregroundStyle(Theme.muted)
                }
            }

            if zoom.isZoomed {
                Text("\(zoom.percent)%")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.gold)
            }

            Button("Delete") { model.deleteCurrent() }
                .buttonStyle(.plain)
                .foregroundStyle(Color(red: 0.72, green: 0.28, blue: 0.22))
                .help("Move this photo to Trash. ⌘Z restores it.")
            Button("Export") { model.showingExport = true }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.muted)
            if !model.toast.isEmpty {
                Text(model.toast)
                    .foregroundStyle(Theme.gold)
                    .lineLimit(1)
            }

            Spacer()
            if !model.photos.isEmpty {
                Text("\(model.index + 1) / \(model.photos.count)")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }
            HStack(spacing: 5) {
                Circle().fill(Theme.saved).frame(width: 6, height: 6)
                Text("Saved")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }
        }
        .font(.system(size: 12.5))
    }

    private func seg(_ title: String, on: Bool, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Text("\(count)")
                    .foregroundStyle(Theme.gold)
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(on ? Theme.card : .clear, in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(on ? Theme.text : Theme.muted)
        }
        .buttonStyle(.plain)
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(on ? Theme.card : .clear, in: Capsule())
                .overlay(Capsule().stroke(on ? Theme.line : .clear))
                .foregroundStyle(on ? Theme.text : Theme.dim)
        }
        .buttonStyle(.plain)
        .font(.system(size: 11.5))
    }

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 3, pinnedViews: []) {
                    ForEach(Array(model.photos.enumerated()), id: \.element.tileID) { i, photo in
                        stripTile(i: i, photo: photo)
                            .id(photo.tileID)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: model.index) { _, _ in
                if let id = model.current?.tileID {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .frame(height: 44)
        .contentShape(Rectangle())
        .background(.regularMaterial)
    }

    private func stripTile(i: Int, photo: PhotoRecord) -> some View {
        let on = i == model.index
        let starred = model.isShortlisted(photo)
        return Button {
            model.index = i
            model.persistSession()
        } label: {
            ZStack(alignment: .topTrailing) {
                ThumbView(
                    url: model.canonicalURL(for: photo),
                    cacheKey: photo.canonicalPath,
                    cacheDir: model.thumbCacheDir
                )
                    .frame(width: 56, height: 42)
                    .clipShape(Rectangle())
                if starred {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.black)
                        .padding(2)
                        .background(Theme.gold, in: Circle())
                        .padding(4)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(on ? Theme.text : Color.clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private var keys: some View {
        HStack(spacing: 16) {
            if model.showGrid {
                keycap("G", "loupe")
                keycap("pgup pgdn", "jump")
                keycap("space", model.viewMode == .shortlist ? "remove" : "add")
                keycap("X", model.viewMode == .shortlist ? "remove" : "pass")
                keycap("delete", "trash")
                keycap("⌘Z", "undo")
            } else if zoom.isZoomed {
                keycap("← ↑ ↓ →", "pan")
                keycap("Z", "zoom in")
                keycap("O", "zoom out")
                keycap("F", "fit")
                keycap("G", "grid")
                keycap("delete", "trash")
            } else {
                keycap("← →", "photos")
                keycap("Z", "zoom in")
                keycap("O", "zoom out")
                keycap("G", "grid")
                keycap("space", model.viewMode == .shortlist ? "remove" : "add")
                keycap("X", model.viewMode == .shortlist ? "remove" : "pass")
                keycap("delete", "trash")
                keycap("⌘Z", "undo")
                keycap("N", "note")
                keycap("/", "jump")
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(Theme.muted)
        .frame(maxWidth: .infinity)
    }

    private var overlayField: some View {
        HStack(spacing: 10) {
            Text(overlay == .note ? "Note" : "Jump")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.gold)
                .frame(width: 36, alignment: .leading)
            TextField(overlay == .note ? "What should the photographer know?" : "M3F03442 or AKHI0355", text: $overlayText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .focused($overlayFocused)
                .onSubmit { submitOverlay() }
            Button("Esc") { closeOverlay() }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.dim)
                .font(.system(size: 11))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
        .onAppear { overlayFocused = true }
    }

    private func openNote() {
        guard let photo = model.current else { return }
        overlayText = model.note(for: photo)
        overlay = .note
        overlayFocused = true
    }

    private func openJump() {
        overlayText = ""
        overlay = .jump
        overlayFocused = true
    }

    private func submitOverlay() {
        switch overlay {
        case .note:
            if let photo = model.current {
                model.setNote(overlayText, on: photo)
            }
            closeOverlay()
        case .jump:
            if model.jump(to: overlayText) {
                closeOverlay()
            }
        case .none:
            break
        }
    }

    private func closeOverlay() {
        overlay = .none
        overlayText = ""
        overlayFocused = false
    }

    private func keycap(_ key: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 10, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.chrome, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line))
            Text(label)
        }
    }

    private func installKeys() {
        removeKeys()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if handle(event) { return nil }
            return event
        }
    }

    private func removeKeys() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        if overlay != .none {
            if event.keyCode == 53 {
                closeOverlay()
                return true
            }
            return false
        }
        let cmd = event.modifierFlags.contains(.command)
        if cmd, event.charactersIgnoringModifiers?.lowercased() == "z" {
            model.undo()
            return true
        }
        if cmd, event.keyCode == 51 || event.keyCode == 117 {
            if !event.isARepeat { model.deleteCurrent() }
            return true
        }
        if cmd { return false }

        let ch = event.charactersIgnoringModifiers?.lowercased()

        // Hold-repeat is for pan / skimming only.
        if event.isARepeat {
            if zoom.isZoomed, [123, 124, 125, 126].contains(event.keyCode) {
                return pan(keyCode: event.keyCode)
            }
            if !zoom.isZoomed, [123, 124].contains(event.keyCode) {
                model.go(event.keyCode == 123 ? -1 : 1)
                return true
            }
            return false
        }

        if ch == "z" || event.keyCode == 6 {
            zoom.zoomIn(cursor: zoomAnchor, viewport: viewport, imageSize: imageSize)
            return true
        }
        if ch == "o" {
            zoom.zoomOut(cursor: zoomAnchor, viewport: viewport, imageSize: imageSize)
            return true
        }
        if ch == "f" {
            zoom.fit()
            return true
        }
        if ch == "g" {
            model.toggleGrid()
            return true
        }
        if model.showGrid {
            switch event.keyCode {
            case 116: model.go(-18); return true // page up
            case 121: model.go(18); return true  // page down
            case 115: model.go(-model.index); return true // home
            case 119: model.go(model.photos.count); return true // end
            default: break
            }
        }
        if ch == "n" {
            openNote()
            return true
        }
        if ch == "/" {
            openJump()
            return true
        }

        if zoom.isZoomed, [123, 124, 125, 126].contains(event.keyCode) {
            return pan(keyCode: event.keyCode)
        }

        switch event.keyCode {
        case 123: model.go(-1); return true
        case 124: model.go(1); return true
        case 49: model.space(); return true
        case 51, 117:
            model.deleteCurrent()
            return true
        default:
            if ch == "x" {
                model.pass()
                return true
            }
            if ch == "u" {
                model.unmark()
                return true
            }
            return false
        }
    }

    /// Arrows walk the viewport across the photo (see more of that side).
    @discardableResult
    private func pan(keyCode: UInt16) -> Bool {
        let stepX = max(viewport.width * 0.16, 64)
        let stepY = max(viewport.height * 0.16, 64)
        switch keyCode {
        case 123: zoom.panBy(dx: stepX, dy: 0, viewport: viewport, imageSize: imageSize)
        case 124: zoom.panBy(dx: -stepX, dy: 0, viewport: viewport, imageSize: imageSize)
        case 126: zoom.panBy(dx: 0, dy: stepY, viewport: viewport, imageSize: imageSize)
        case 125: zoom.panBy(dx: 0, dy: -stepY, viewport: viewport, imageSize: imageSize)
        default: return false
        }
        return true
    }
}


