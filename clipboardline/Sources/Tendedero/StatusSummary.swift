import AppKit

struct StatusSummary: Equatable {
    let images: Int
    let texts: Int
    let links: Int
    var count: Int { images + texts + links }
    var badge: String { count > 9 ? "9+" : String(count) }
    var description: String {
        count == 0 ? L("The line is empty") : String(format: L("%d images · %d texts · %d links on the line"), images, texts, links)
    }
    @MainActor init(line: Line) {
        images = line.presentation.shelves.contains(.images) ? line.liveCount : 0
        texts = line.presentation.shelves.contains(.texts) ? line.texts.entries.count : 0
        links = line.presentation.shelves.contains(.links) ? line.links.entries.count : 0
    }
    init(images: Int, texts: Int, links: Int) { self.images = max(0, images); self.texts = max(0, texts); self.links = max(0, links) }
    func image(symbol: NSImage) -> NSImage {
        let label = NSAttributedString(string: badge, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: count > 9 ? 7 : 8, weight: .bold), .foregroundColor: NSColor.black])
        let size = symbol.size, text = label.size()
        let rect = NSRect(x: size.width - max(text.height, text.width + 2), y: 0, width: max(text.height, text.width + 2), height: text.height)
        let result = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            symbol.draw(in: NSRect(origin: .zero, size: size))
            ctx.setBlendMode(.destinationOut); NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: -1), xRadius: rect.height / 2 + 1, yRadius: rect.height / 2 + 1).fill()
            ctx.setBlendMode(.normal); NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            ctx.setBlendMode(.destinationOut); label.draw(at: NSPoint(x: rect.midX - text.width / 2, y: rect.minY))
            return true
        }
        result.isTemplate = true; result.accessibilityDescription = description
        return result
    }
}
