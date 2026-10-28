import AppKit

private final class LinkPreviewDocument: NSView {
    override var isFlipped: Bool { true }
}

/// YouTube's hqdefault thumbnails often wrap a 16:9 image in a 4:3 black
/// canvas. Crop only verified black padding, never a real 4:3 thumbnail.
enum LinkThumbnail {
    static func removingYouTubeLetterbox(_ image: NSImage) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), cg.width >= 160,
              abs(Double(cg.width) / Double(cg.height) - 4.0 / 3.0) < 0.03 else { return image }
        let width = cg.width, height = cg.height, target = Int((Double(width) * 9 / 16).rounded())
        let padding = (height - target) / 2
        guard padding > 2 else { return image }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let isPadded = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            let pixels = buffer.bindMemory(to: UInt8.self)
            func black(_ x: Int, _ y: Int) -> Bool { let i = (y * width + x) * 4; return pixels[i] < 20 && pixels[i + 1] < 20 && pixels[i + 2] < 20 && pixels[i + 3] > 245 }
            // Leave a two-pixel JPEG boundary tolerance, but check the complete
            // padding height and sample across the full width.
            for y in 0..<(padding - 2) {
                for x in stride(from: 0, to: width, by: max(1, width / 128)) {
                    if !black(x, y) || !black(x, height - 1 - y) { return false }
                }
            }
            return stride(from: 0, to: width, by: max(1, width / 128)).contains { !black($0, height / 2) }
        }
        guard isPadded, let cropped = cg.cropping(to: CGRect(x: 0, y: padding, width: width, height: target)) else { return image }
        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }
}

@MainActor final class LinkPreview: NSObject, NSWindowDelegate {
    let window: ActionPreviewPanel
    let controls = PreviewControls()
    private let image = NSImageView()
    private let title = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let address = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let thumbs = ThumbnailStore()
    private var record: LibraryRecord
    private var displayedID: UUID?
    private var displayedThumbnail: String?
    private var copiedUntil = Date.distantPast
    var onKey: ((NSEvent) -> Bool)?
    var onClose: (() -> Void)?
    var onOpen: (URL) -> Void = { NSWorkspace.shared.open($0) }
    private(set) var hasThumbnail = false
    init(record: LibraryRecord, keyboardBindings: KeyboardBindings? = nil, window existing: ActionPreviewPanel? = nil) {
        self.record = record
        let visible = (existing?.screen ?? LinePanel.screenUnderPointer())?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 750)
        window = makePreviewPanel(size: NSSize(width: min(660, visible.width * 0.8), height: min(650, visible.height * 0.85)), reusing: existing)
        super.init()
        controls.keyboardBindings = keyboardBindings ?? KeyboardBindings(defaults: .standard)
        window.title = L("Link preview"); window.delegate = self; window.level = .floating
        window.isReleasedWhenClosed = false; window.hidesOnDeactivate = false
        window.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true; window.isMovableByWindowBackground = true
        let surface = NSVisualEffectView(); surface.material = .hudWindow; surface.blendingMode = .behindWindow; surface.state = .active
        surface.wantsLayer = true; surface.layer?.cornerRadius = 20; surface.layer?.masksToBounds = true
        image.imageScaling = .scaleProportionallyUpOrDown
        image.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        image.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        image.setContentHuggingPriority(.defaultLow, for: .horizontal)
        image.setContentHuggingPriority(.defaultLow, for: .vertical)
        image.setAccessibilityLabel(L("Link thumbnail")); image.wantsLayer = true
        image.layer?.cornerRadius = 12; image.layer?.masksToBounds = true
        title.font = .systemFont(ofSize: 21, weight: .semibold); title.maximumNumberOfLines = 3
        detail.font = .systemFont(ofSize: 12); detail.textColor = .secondaryLabelColor
        address.font = .systemFont(ofSize: 11); address.textColor = .secondaryLabelColor; address.maximumNumberOfLines = 2
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        for label in [title, detail, address, status] { label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) }
        let open = NSButton(title: L("Open in browser"), target: self, action: #selector(openLink)); open.bezelStyle = .rounded
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.setViews([image, title, detail, address], in: .top)
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.borderType = .noBorder
        let document = LinkPreviewDocument(); document.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true; scroll.scrollerStyle = .overlay; scroll.documentView = document
        document.addSubview(stack)
        let footer = NSStackView(views: [open, status]); footer.spacing = 12
        for view in [controls, scroll, footer] { view.translatesAutoresizingMaskIntoConstraints = false; surface.addSubview(view) }
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controls.topAnchor.constraint(equalTo: surface.topAnchor, constant: 16), controls.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -20),
            scroll.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 14), scroll.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 24), scroll.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -24), scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -14),
            footer.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 24), footer.trailingAnchor.constraint(lessThanOrEqualTo: surface.trailingAnchor, constant: -24), footer.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -20),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor), stack.topAnchor.constraint(equalTo: document.topAnchor), stack.trailingAnchor.constraint(equalTo: document.trailingAnchor), stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            image.heightAnchor.constraint(equalTo: image.widthAnchor, multiplier: 9.0 / 16.0), image.widthAnchor.constraint(equalTo: stack.widthAnchor), title.widthAnchor.constraint(equalTo: stack.widthAnchor), detail.widthAnchor.constraint(equalTo: stack.widthAnchor), address.widthAnchor.constraint(equalTo: stack.widthAnchor)])
        window.contentView = surface; if existing == nil { window.center() }
        controls.onClose = { [weak self] in self?.window.close() }
        window.onKey = { [weak self] event in
            guard let self else { return false }
            let action = self.controls.keyboardBindings.action(for: event, in: .linkPreview)
            if action == .close || action == .preview { self.window.close(); return true }
            if action == .open { self.openCurrent(); return true }
            return self.onKey?(event) ?? false
        }
        thumbs.onLoad = { [weak self] in self?.refreshThumbnail() }
        replace(record)
    }
    func replace(_ record: LibraryRecord) {
        let changedImage = displayedID != record.id || displayedThumbnail != record.thumbnailPath
        if displayedID != record.id { copiedUntil = .distantPast }
        self.record = record; title.stringValue = record.displayTitle
        detail.stringValue = [record.author, record.linkURL?.host].compactMap { $0 }.joined(separator: " · ")
        address.stringValue = record.originalURL ?? ""
        if Date() >= copiedUntil { status.stringValue = record.metadataState == "failed" ? L("Preview unavailable; your link is saved") : controls.keyboardBindings.title(.open) + " · " + L("Open in browser") }
        if changedImage {
            hasThumbnail = false; showPlaceholder()
            if let path = record.thumbnailPath { thumbs.request([URL(fileURLWithPath: path)], pixels: 1000); refreshThumbnail() }
        }
        displayedID = record.id; displayedThumbnail = record.thumbnailPath
    }
    private func showPlaceholder() { image.imageScaling = .scaleNone; image.image = NSImage(systemSymbolName: "link", accessibilityDescription: L("Link"))?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 48, weight: .light)) }
    private func refreshThumbnail() {
        if let path = record.thumbnailPath, let thumbnail = thumbs.image(for: URL(fileURLWithPath: path), pixels: 1000) {
            image.imageScaling = .scaleProportionallyUpOrDown
            image.image = record.linkURL.flatMap(LinkIdentity.youtubeID) != nil ? LinkThumbnail.removingYouTubeLetterbox(thumbnail) : thumbnail
            hasThumbnail = true
        }
    }
    func flashCopied() {
        copiedUntil = Date().addingTimeInterval(1.2); let id = record.id
        status.stringValue = L("Link copied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) { [weak self] in
            guard let self, self.record.id == id, Date() >= self.copiedUntil else { return }; self.replace(self.record)
        }
    }
    func show() { window.makeKeyAndOrderFront(nil) }
    func windowWillClose(_ notification: Notification) { onClose?() }
    func openCurrent() { if let url = record.linkURL, ["https", "http"].contains(url.scheme?.lowercased() ?? "") { onOpen(url) } }
    @objc private func openLink() { openCurrent() }
}
