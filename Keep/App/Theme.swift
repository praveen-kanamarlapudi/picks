import AppKit
import SwiftUI

enum Theme {
    /// Warm paper, not stark white.
    static let bg = Color(red: 0.96, green: 0.955, blue: 0.94)
    static let chrome = Color(red: 0.94, green: 0.935, blue: 0.92)
    static let card = Color.white
    static let text = Color(red: 0.13, green: 0.13, blue: 0.13)
    static let muted = Color(red: 0.38, green: 0.37, blue: 0.35)
    static let dim = Color(red: 0.56, green: 0.55, blue: 0.52)
    static let gold = Color(red: 0.62, green: 0.44, blue: 0.14)
    static let goldDim = Color(red: 0.62, green: 0.44, blue: 0.14).opacity(0.14)
    static let line = Color.black.opacity(0.10)
    static let saved = Color(red: 0.22, green: 0.55, blue: 0.38)
    static let photoWell = Color(red: 0.90, green: 0.89, blue: 0.87)
}

enum AppChrome {
    static func preferLegacyScrollers() {}
}

/// NSViewRepresentable backgrounds sit in the AppKit tree and steal clicks
/// unless hit-testing is opted out. Used by WindowAccessor + scroller helper.
final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Forces a grab-able scroller on the enclosing SwiftUI ScrollView.
struct AlwaysShowScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        DispatchQueue.main.async { Self.apply(from: view) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        Self.apply(from: view)
    }

    private static func apply(from view: NSView) {
        guard let root = view.window?.contentView ?? view.superview else { return }
        walk(root)
    }

    private static func walk(_ view: NSView) {
        if let scroll = view as? NSScrollView {
            // Vertical lists only. Never force a fat bar under the filmstrip.
            let tall = scroll.frame.height >= 80
            if tall {
                scroll.scrollerStyle = .legacy
                scroll.hasVerticalScroller = true
                scroll.autohidesScrollers = false
                scroll.scrollerKnobStyle = .default
                scroll.verticalScroller?.controlSize = .regular
                scroll.verticalScroller?.alphaValue = 1
            }
            scroll.hasHorizontalScroller = false
        }
        view.subviews.forEach(walk)
    }
}
