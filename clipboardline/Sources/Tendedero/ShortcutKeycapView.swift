import AppKit
import CoreText

/// Centers the visible glyphs, rather than NSTextField's font line box.
/// Core Text includes fallback glyphs used for modifiers and arrow symbols.
@MainActor final class ShortcutKeycapView: NSView {
    private let line: CTLine
    private let inkBounds: CGRect
    private let keycapSize: NSSize

    init(_ title: String) {
        let font = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
        line = CTLineCreateWithAttributedString(NSAttributedString(string: title, attributes: [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true
        ]))
        inkBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        keycapSize = NSSize(width: max(title == "↑ ↓" ? 28 : 22, ceil(max(advance, inkBounds.width) + 10)), height: 18)
        super.init(frame: NSRect(origin: .zero, size: keycapSize))
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(title)
        setAccessibilityValue(title)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { keycapSize }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), xRadius: 4, yRadius: 4)
        NSColor.labelColor.withAlphaComponent(0.055).setFill()
        outline.fill()
        NSColor.labelColor.withAlphaComponent(0.08).setStroke()
        outline.lineWidth = 0.5
        outline.stroke()
        guard !inkBounds.isEmpty, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.textMatrix = .identity
        context.setFillColor(NSColor.secondaryLabelColor.cgColor)
        context.textPosition = CGPoint(x: bounds.midX - inkBounds.midX, y: bounds.midY - inkBounds.midY)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
