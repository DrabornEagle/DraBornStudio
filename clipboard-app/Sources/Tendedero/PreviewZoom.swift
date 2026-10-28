import AppKit

struct PreviewZoom {
    private(set) var scale: CGFloat = 1
    static let range: ClosedRange<CGFloat> = 1...4
    mutating func wheel(_ delta: CGFloat, precise: Bool) {
        guard delta.isFinite else { return }
        scale = max(Self.range.lowerBound, min(Self.range.upperBound,
            scale * exp(max(-100, min(100, delta)) * (precise ? 0.012 : 0.09))))
    }
    mutating func reset() { scale = 1 }
    mutating func magnify(_ delta: CGFloat) {
        guard delta.isFinite else { return }
        scale = max(Self.range.lowerBound, min(Self.range.upperBound, scale * max(0.01, 1 + delta)))
    }
}

final class ZoomScrollView: NSScrollView {
    private(set) var zoom = PreviewZoom()
    var fittedSize = NSSize(width: 640, height: 420)
    var onHover: ((Bool) -> Void)?
    private var hoverTracking: NSTrackingArea?
    private var panStart: (point: NSPoint, origin: NSPoint)?
    var canPan: Bool { zoom.scale > PreviewZoom.range.lowerBound }
    /// Clip/document coordinates share the image's orientation. NSScrollView's
    /// own coordinates are flipped and would reverse vertical hand dragging.
    func viewportPoint(for event: NSEvent) -> NSPoint {
        let point = contentView.convert(event.locationInWindow, from: nil)
        return NSPoint(x: point.x - contentView.bounds.minX, y: point.y - contentView.bounds.minY)
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        if canPan { addCursorRect(visibleRect, cursor: .openHand) }
    }
    @discardableResult func beginPan(at point: NSPoint) -> Bool {
        guard canPan else { return false }
        panStart = (point, contentView.bounds.origin)
        NSCursor.closedHand.push()
        return true
    }
    func pan(to point: NSPoint) {
        guard let start = panStart else { return }
        scroll(to: NSPoint(x: start.origin.x - (point.x - start.point.x),
            y: start.origin.y - (point.y - start.point.y)))
    }
    func endPan() {
        guard panStart != nil else { return }
        panStart = nil; NSCursor.pop()
    }
    private func scroll(to point: NSPoint) {
        guard let documentView else { return }
        contentView.scroll(to: NSPoint(
            x: max(0, min(max(0, documentView.frame.width - contentView.bounds.width), point.x)),
            y: max(0, min(max(0, documentView.frame.height - contentView.bounds.height), point.y))))
        reflectScrolledClipView(contentView)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); hoverTracking = area
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    var onZoom: ((CGFloat) -> Void)?
    override func magnify(with event: NSEvent) {
        let old = zoom.scale
        zoom.magnify(event.magnification)
        apply(oldScale: old, anchor: viewportPoint(for: event))
    }
    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX), !event.modifierFlags.contains(.shift) else {
            super.scrollWheel(with: event); return
        }
        let old = zoom.scale
        zoom.wheel(event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas)
        apply(oldScale: old, anchor: viewportPoint(for: event))
    }
    @objc func resetZoom() {
        endPan()
        let old = zoom.scale; zoom.reset()
        apply(oldScale: old, anchor: NSPoint(x: contentView.bounds.width / 2, y: contentView.bounds.height / 2))
    }
    private func apply(oldScale: CGFloat, anchor: NSPoint) {
        guard let documentView else { return }
        let point = NSPoint(x: (contentView.bounds.origin.x + anchor.x) / oldScale,
            y: (contentView.bounds.origin.y + anchor.y) / oldScale)
        documentView.setFrameSize(NSSize(width: fittedSize.width * zoom.scale, height: fittedSize.height * zoom.scale))
        let x = max(0, min(max(0, documentView.frame.width - contentView.bounds.width), point.x * zoom.scale - anchor.x))
        let y = max(0, min(max(0, documentView.frame.height - contentView.bounds.height), point.y * zoom.scale - anchor.y))
        contentView.scroll(to: NSPoint(x: x, y: y)); reflectScrolledClipView(contentView)
        window?.invalidateCursorRects(for: self)
        onZoom?(zoom.scale)
    }
}
