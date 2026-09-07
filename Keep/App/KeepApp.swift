import SwiftUI

@main
struct KeepApp: App {
    @State private var model = AppModel()

    init() {
        AppChrome.preferLegacyScrollers()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.gold)
                .foregroundStyle(Theme.text)
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Dump…") { model.chooseFolder() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Export Shortlist…") { model.showingExport = true }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.db == nil)
                Button("Move Photo to Trash") { model.deleteCurrent() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(model.route != .review || model.current == nil)
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch model.route {
            case .open:
                OpenView()
            case .scan:
                ScanView()
            case .home:
                EventHomeView()
            case .review:
                ReviewView()
            }
        }
        .background(WindowAccessor())
        .sheet(isPresented: Binding(
            get: { model.showingExport },
            set: { model.showingExport = $0 }
        )) {
            ExportSheet()
                .environment(model)
        }
        .alert("Keep", isPresented: Binding(
            get: { model.errorText != nil },
            set: { if !$0 { model.errorText = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorText = nil }
        } message: {
            Text(model.errorText ?? "")
        }
    }
}

/// Lets the content draw under traffic lights.
private struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = false
            window.backgroundColor = NSColor(Theme.bg)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
