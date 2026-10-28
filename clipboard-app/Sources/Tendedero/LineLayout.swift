import Foundation

enum Layout {
    enum Size: String, CaseIterable {
        case small, medium, large
        var scale: CGFloat { switch self { case .small: 0.8; case .medium: 1; case .large: 1.35 } }
    }
    // One layout per application. The model persists this in its injected suite.
    static var size: Size = .medium
    static var maximumRowHeight = CGFloat.greatestFiniteMagnitude
    static var scale: CGFloat { min(size.scale, max(0.6, (maximumRowHeight - 98) / 104)) }
    static var photoMaxHeight: CGFloat { floor(104 * scale) }
    static var panelHeight: CGFloat { 202 + photoMaxHeight - 104 }
    // Keep pins and cards below the compact row controls, even at the edges.
    static let ropeTop: CGFloat = 32
    static var spacing: CGFloat { cardWidth + 24 }
    static var cardWidth: CGFloat { (150 * scale).rounded() }
    static let pinAbove: CGFloat = 9.5
    static let edgePadding: CGFloat = 24

    static func sag(width: CGFloat) -> CGFloat { min(30, width * 0.018) }

    static func ropeY(x: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return ropeTop }
        let f = max(0, min(1, x / width))
        return ropeTop + 4 * sag(width: width) * f * (1 - f)
    }

    static func x(index: Int, scrollOffset: CGFloat = 0) -> CGFloat {
        edgePadding + cardWidth / 2 + CGFloat(index) * spacing - scrollOffset
    }

    static func contentWidth(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return edgePadding * 2 + cardWidth + CGFloat(count - 1) * spacing
    }

    static func maximumOffset(count: Int, width: CGFloat) -> CGFloat {
        max(0, contentWidth(count: count) - max(1, width))
    }

    /// A one-card buffer keeps entering views ready without decoding the
    /// entire month's history or constructing off-screen SwiftUI cards.
    static func visibleRange(count: Int, width: CGFloat, offset: CGFloat) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        let first = max(0, Int(floor(max(0, offset) / spacing)) - 1)
        let last = min(count, Int(ceil((max(0, offset) + max(1, width)) / spacing)) + 1)
        return min(first, last)..<last
    }
}
