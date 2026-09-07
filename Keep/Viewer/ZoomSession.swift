import CoreGraphics
import Foundation

/// Stepped zoom like Preview / FastRawViewer, not a binary 1:1 toggle.
struct ZoomSession: Equatable {
    static let steps: [CGFloat] = [1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0]

    var step: Int = 0
    var pan: CGSize = .zero

    var scale: CGFloat { Self.steps[step] }
    var isZoomed: Bool { step > 0 }
    var percent: Int { Int((scale * 100).rounded()) }
    var canZoomIn: Bool { step < Self.steps.count - 1 }
    var canZoomOut: Bool { step > 0 }

    mutating func zoomIn(cursor: CGPoint, viewport: CGSize, imageSize: CGSize) {
        guard canZoomIn else { return }
        let old = scale
        step += 1
        keepCursorFixed(from: old, to: scale, cursor: cursor, viewport: viewport)
        clamp(viewport: viewport, imageSize: imageSize)
    }

    mutating func zoomOut(cursor: CGPoint, viewport: CGSize, imageSize: CGSize) {
        guard canZoomOut else { return }
        let old = scale
        step -= 1
        if step == 0 {
            pan = .zero
            return
        }
        keepCursorFixed(from: old, to: scale, cursor: cursor, viewport: viewport)
        clamp(viewport: viewport, imageSize: imageSize)
    }

    mutating func fit() {
        step = 0
        pan = .zero
    }

    /// Arrow / drag: positive dx moves the image right (content follows the hand).
    mutating func panBy(dx: CGFloat, dy: CGFloat, viewport: CGSize, imageSize: CGSize) {
        guard isZoomed else { return }
        pan.width += dx
        pan.height += dy
        clamp(viewport: viewport, imageSize: imageSize)
    }

    mutating func setPan(_ value: CGSize, viewport: CGSize, imageSize: CGSize) {
        pan = value
        clamp(viewport: viewport, imageSize: imageSize)
    }

    mutating func clamp(viewport: CGSize, imageSize: CGSize) {
        let limit = maxPan(viewport: viewport, imageSize: imageSize)
        pan.width = min(max(pan.width, -limit.width), limit.width)
        pan.height = min(max(pan.height, -limit.height), limit.height)
        if !isZoomed { pan = .zero }
    }

    func maxPan(viewport: CGSize, imageSize: CGSize) -> CGSize {
        let iw = max(imageSize.width, 1)
        let ih = max(imageSize.height, 1)
        let vw = max(viewport.width, 1)
        let vh = max(viewport.height, 1)
        let fit = min(vw / iw, vh / ih)
        let shown = CGSize(width: iw * fit * scale, height: ih * fit * scale)
        return CGSize(
            width: max(0, (shown.width - vw) / 2),
            height: max(0, (shown.height - vh) / 2)
        )
    }

    /// Keep the point under the cursor stuck to the same photo pixel.
    private mutating func keepCursorFixed(from old: CGFloat, to new: CGFloat, cursor: CGPoint, viewport: CGSize) {
        let center = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let rel = CGSize(width: cursor.x - center.x, height: cursor.y - center.y)
        let ratio = new / max(old, 0.001)
        pan = CGSize(
            width: rel.width * (1 - ratio) + pan.width * ratio,
            height: rel.height * (1 - ratio) + pan.height * ratio
        )
    }
}
