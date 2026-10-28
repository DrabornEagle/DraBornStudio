import AppKit

private final class PreviewTextView: NSTextView {
    var onBeginEditing: (() -> Void)?
    var onCopied: (() -> Void)?
    var copyPasteboard: NSPasteboard?
    override func mouseDown(with event: NSEvent) { onBeginEditing?(); super.mouseDown(with: event) }
    override func copy(_ sender: Any?) {
        if let copyPasteboard {
            let range = selectedRange()
            guard range.length > 0, NSMaxRange(range) <= (string as NSString).length else { return }
            guard ClipboardTransfer.write(ClipboardTransfer.textItems([(string as NSString).substring(with: range)]), to: copyPasteboard) else { return }
        } else {
            super.copy(sender); ClipboardWatcher.recordOwnCopy(changeCount: NSPasteboard.general.changeCount)
        }
        onCopied?()
    }
}

@MainActor
final class TextPreview: NSObject, NSWindowDelegate, NSTextViewDelegate {
    let window: NSPanel
    let textView: NSTextView
    let controls = PreviewControls(editable: true)
    private let status = NSTextField(labelWithString: "")
    private var pendingSave: DispatchWorkItem?
    private var dirty = false
    private(set) var isEditing = false
    let keyboardBindings: KeyboardBindings
    var onClose: (() -> Void)?
    var onKey: ((NSEvent) -> Bool)?
    var onSave: ((String) -> Bool)?

    init(text: String, copyPasteboard: NSPasteboard? = nil, keyboardBindings: KeyboardBindings? = nil, window existing: ActionPreviewPanel? = nil) {
        self.keyboardBindings = keyboardBindings ?? KeyboardBindings(defaults: .standard)
        let visible = (existing?.screen ?? LinePanel.screenUnderPointer())?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 750)
        let width = min(680, visible.width * 0.8)
        let lines = min(18, max(4, text.prefix(10000).split(separator: "\n", omittingEmptySubsequences: false).count))
        let height = min(visible.height * 0.72, max(260, CGFloat(lines) * 24 + 100))
        let panel = makePreviewPanel(size: NSSize(width: width, height: height), reusing: existing)
        window = panel
        let editor = PreviewTextView(frame: NSRect(x: 0, y: 0, width: width - 48, height: height - 105))
        textView = editor
        editor.copyPasteboard = copyPasteboard
        super.init()
        controls.keyboardBindings = self.keyboardBindings
        panel.onKey = { [weak self] in self?.routeKey($0) ?? false }
        window.title = L("Text preview"); window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false; window.delegate = self; window.level = .floating
        window.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.isMovableByWindowBackground = true
        let surface = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        surface.material = .hudWindow; surface.blendingMode = .behindWindow; surface.state = .active
        surface.wantsLayer = true; surface.layer?.cornerRadius = 20; surface.layer?.masksToBounds = true
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true; scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        editor.string = text; editor.isEditable = false; editor.isSelectable = true; editor.isRichText = false
        editor.drawsBackground = false; editor.textColor = .labelColor; editor.font = .systemFont(ofSize: 17)
        editor.textContainerInset = NSSize(width: 4, height: 8)
        editor.isHorizontallyResizable = false; editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: width - 48, height: .greatestFiniteMagnitude)
        editor.delegate = self; editor.allowsUndo = true; editor.setAccessibilityLabel(L("Text preview"))
        editor.onBeginEditing = { [weak self] in self?.beginEditing() }
        editor.onCopied = { [weak self] in self?.flashCopied() }
        scroll.documentView = editor
        controls.translatesAutoresizingMaskIntoConstraints = false
        status.translatesAutoresizingMaskIntoConstraints = false; status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.stringValue = browsingHint
        surface.addSubview(scroll); surface.addSubview(controls); surface.addSubview(status)
        NSLayoutConstraint.activate([
            controls.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -16),
            controls.topAnchor.constraint(equalTo: surface.topAnchor, constant: 12),
            scroll.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -20),
            scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -8),
            status.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 24),
            status.trailingAnchor.constraint(lessThanOrEqualTo: surface.trailingAnchor, constant: -20),
            status.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -14)])
        controls.onEdit = { [weak self] in guard let self else { return }; if self.isEditing { _ = self.finishEditing() } else { self.beginEditing() } }
        controls.onClose = { [weak self] in self?.requestClose() }
        window.contentView = surface
        if existing == nil { window.setFrameOrigin(NSPoint(x: visible.midX - width / 2, y: visible.midY - height / 2)) }
    }
    func show() { window.makeKeyAndOrderFront(nil); window.makeFirstResponder(nil) }
    func beginEditing() {
        isEditing = true; textView.isEditable = true; window.makeFirstResponder(textView)
        controls.setEditing(true)
        status.stringValue = L("Editing · changes are saved automatically") + " · " + keyboardBindings.title(.finishEditing) + " " + L("Finish editing")
    }
    @discardableResult func finishEditing() -> Bool {
        guard flushEdits() else { return false }
        isEditing = false; textView.isEditable = false; window.makeFirstResponder(nil)
        controls.setEditing(false); status.stringValue = browsingHint; return true
    }
    private var browsingHint: String { L("Click the text to edit") + " · " + keyboardBindings.title(.previous) + "/" + keyboardBindings.title(.next) + " " + L("Preview") + " · " + keyboardBindings.title(.pin) + " " + L("Pin favorite") }
    func textDidChange(_ notification: Notification) {
        dirty = true; pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in _ = self?.flushEdits() }
        pendingSave = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    @discardableResult func flushEdits() -> Bool {
        pendingSave?.cancel(); pendingSave = nil
        guard dirty else { return true }
        guard onSave?(textView.string) ?? true else {
            status.stringValue = L("Could not save text history"); return false
        }
        dirty = false; status.stringValue = L("Changes saved"); return true
    }
    func replaceText(_ text: String) {
        pendingSave?.cancel(); pendingSave = nil; dirty = false
        textView.string = text; textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0)); textView.undoManager?.removeAllActions()
        isEditing = false; textView.isEditable = false; window.makeFirstResponder(nil)
        controls.setEditing(false); status.stringValue = browsingHint
    }
    func flashCopied() { status.stringValue = L("Text copied") }
    func requestClose() { if flushEdits() { window.close() } }
    func routeKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .control, .option])
        let action = keyboardBindings.action(for: event, in: .textPreview)
        if isEditing {
            if action == .finishEditing || keyboardBindings.matches(.finishEditing, event: event) || (event.keyCode == 53 && flags.isEmpty) { _ = finishEditing(); return true }
            if !flags.intersection([.command, .control]).isEmpty && (action == .pin || action == .pinnedOnly || action == .commandPalette) { return onKey?(event) ?? false }
            return false
        }
        if action == .finishEditing, keyboardBindings.matches(.paste, event: event) { return onKey?(event) ?? false }
        if action == .close || action == .preview { requestClose(); return true }
        if action == .editText { beginEditing(); return true }
        return onKey?(event) ?? false
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { flushEdits() }
    func windowWillClose(_ notification: Notification) { pendingSave?.cancel(); onClose?() }
}
