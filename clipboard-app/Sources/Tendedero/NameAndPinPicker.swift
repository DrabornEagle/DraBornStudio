import AppKit

private enum NameAndPinFailure: Error, LocalizedError {
    case unavailable
    var errorDescription: String? { L("This item is no longer available. Press Esc to leave.") }
}

/// A name is metadata, never a replacement for the copied text, URL or pixels.
/// Freeze the ordered selection before opening so later shelf changes cannot
/// broaden the batch or redirect a draft to another item.
@MainActor final class NameAndPinPicker: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    let window: ActionPreviewPanel
    let nameField: PickerSearchField
    let orderedIDs: [UUID]
    private(set) var currentIndex = 0
    var id: UUID { orderedIDs[currentIndex] }
    var progressText: String { orderedIDs.count > 1 ? String(format: L("Item %d of %d"), currentIndex + 1, orderedIDs.count) : "" }
    private(set) var itemContext = ""
    private let store: LibraryStore
    private let surface: NameAndPinSurface
    private var closed = false
    private var confirming = false
    private var lastConfirmEvent: NSEvent?
    private(set) var errorMessage: String?
    var onClose: (() -> Void)?
    var onAdvance: ((UUID) -> Void)?

    convenience init(store: LibraryStore, id: UUID) throws { try self.init(store: store, ids: [id]) }

    init(store: LibraryStore, ids: [UUID]) throws {
        var seen = Set<UUID>()
        let orderedIDs = ids.filter { seen.insert($0).inserted }
        guard !orderedIDs.isEmpty else { throw HistoryFiles.Failure.unsafeFile }
        var firstRecord: LibraryRecord?
        for id in orderedIDs {
            guard let record = try store.item(id), record.deletedAt == nil else { throw NameAndPinFailure.unavailable }
            // Large text payloads need validation, never a batch-sized cache.
            if firstRecord == nil { firstRecord = record }
        }
        guard let firstRecord else { throw NameAndPinFailure.unavailable }
        self.store = store; self.orderedIDs = orderedIDs
        nameField = PickerSearchField(placeholder: L("Add a name for search…"))
        nameField.setAccessibilityIdentifier("name-and-pin-input")
        // Opaque values, a URL and generated link metadata are not custom names.
        surface = NameAndPinSurface(nameField: nameField)
        window = ActionPreviewPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 208),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        window.title = L("Name and pin…"); window.isReleasedWhenClosed = false
        window.delegate = self; window.level = .floating; window.hidesOnDeactivate = false
        window.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.contentView = surface; window.isMovableByWindowBackground = true
        nameField.delegate = self
        surface.onCancel = { [weak self] in self?.window.close() }
        // Mouse and accessibility button actions can have a non-key current
        // event. They must never query keyboard-only NSEvent properties.
        surface.onConfirm = { [weak self] in self?.confirm(event: nil) }
        window.onKey = { [weak self] in self?.handle($0) ?? false }
        load(firstRecord)
    }

    func show(relativeTo parent: NSWindow?) {
        let frame = parent?.screen?.visibleFrame ?? LinePanel.screenUnderPointer()?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 750)
        let size = NSSize(width: min(520, max(240, frame.width - 32)), height: min(208, frame.height - 32))
        window.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height), display: false)
        parent?.addChildWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil); focusName()
    }

    func focusName() { window.makeFirstResponder(nameField); nameField.selectText(nil) }

    @discardableResult func handle(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard modifiers.isEmpty else { return false }
        // The native editor first commits/cancels any input-method composition.
        if let editor = window.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
        if event.keyCode == 53 { window.close(); return true }
        if event.keyCode == 36 || event.keyCode == 76 { confirm(event: event); return true }
        // Typing, selection, arrows, deletion and clipboard commands belong to
        // the native field editor. This panel never forwards them to a shelf.
        return false
    }

    func controlTextDidChange(_ notification: Notification) {
        errorMessage = nil; surface.setMessage(nil)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            let event = NSApp.currentEvent
            confirm(event: event?.type == .keyDown ? event : nil); return true
        case #selector(NSResponder.cancelOperation(_:)): window.close(); return true
        default: return false
        }
    }

    func confirm(event: NSEvent? = nil) {
        guard !closed, !confirming else { return }
        // Holding Enter or routing the same key through both the panel and its
        // native field editor must never accept the next item's prefilled name.
        if let event {
            if (event.type == .keyDown || event.type == .keyUp), event.isARepeat { return }
            guard lastConfirmEvent !== event else { return }
            lastConfirmEvent = event
        }
        confirming = true; defer { confirming = false }
        do {
            guard let current = try store.item(id), current.deletedAt == nil else { throw NameAndPinFailure.unavailable }
            try store.nameAndPin(id, name: nameField.stringValue)
            errorMessage = nil; surface.setMessage(nil)
            guard !closed else { return }
            // A target removed after the batch opened has no draft to save.
            // Skip it without reviving it, and retain the original progress/order.
            for index in orderedIDs.indices.dropFirst(currentIndex + 1) {
                guard let next = try store.item(orderedIDs[index]), next.deletedAt == nil else { continue }
                currentIndex = index; load(next); focusName(); onAdvance?(id)
                return
            }
            window.close()
        } catch {
            errorMessage = error.localizedDescription; surface.setMessage(errorMessage)
            window.makeFirstResponder(nameField)
        }
    }

    private func load(_ record: LibraryRecord) {
        nameField.stringValue = record.title
        let kind = record.kind == .image ? L("Image") : record.kind == .text ? L("Text") : L("Link")
        let detail: String
        if !record.title.isEmpty { detail = record.title }
        else {
            switch record.kind {
            case .text: detail = L("Untitled note")
            case .image: detail = record.exportFileName ?? L("Image")
            case .link:
                let host = record.linkURL?.host ?? L("Link")
                let title = record.metadataTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                detail = title.isEmpty ? host : title + " · " + host
            }
        }
        let singleLine = detail.components(separatedBy: .newlines).joined(separator: " ")
        itemContext = kind + " · " + String(singleLine.prefix(180))
        surface.setItem(progress: progressText, context: itemContext, hasNext: currentIndex + 1 < orderedIDs.count)
    }

    func windowWillClose(_ notification: Notification) {
        guard !closed else { return }
        closed = true; window.makeFirstResponder(nil)
        window.parent?.removeChildWindow(window); onClose?()
    }
}

/// Matches the shelves' and keyboard pickers' quiet rounded search surface.
@MainActor private final class NameAndPinSurface: NSVisualEffectView {
    private let message = NSTextField(wrappingLabelWithString: "")
    private let progress = NSTextField(labelWithString: "")
    private let context = NSTextField(labelWithString: "")
    private let confirm: NSButton
    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?

    init(nameField: NSTextField) {
        confirm = NSButton(title: L("Pin with name"), target: nil, action: nil)
        super.init(frame: .zero)
        material = .hudWindow; blendingMode = .withinWindow; state = .active
        wantsLayer = true; layer?.cornerRadius = 16; layer?.masksToBounds = true
        setAccessibilityIdentifier("name-and-pin-picker")
        let title = NSTextField(labelWithString: L("Name and pin…"))
        title.font = .systemFont(ofSize: 11, weight: .semibold); title.textColor = .secondaryLabelColor
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: L("Close"))!, target: self, action: #selector(cancelPicker))
        close.isBordered = false; close.bezelStyle = .inline; close.setAccessibilityLabel(L("Close"))
        close.widthAnchor.constraint(equalToConstant: 24).isActive = true
        progress.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular); progress.textColor = .secondaryLabelColor
        progress.setAccessibilityIdentifier("name-and-pin-progress")
        let header = NSStackView(views: [title, NSView(), progress, close]); header.spacing = 10
        let icon = NSImageView(image: NSImage(systemSymbolName: "pin", accessibilityDescription: nil)!)
        icon.contentTintColor = .secondaryLabelColor; icon.widthAnchor.constraint(equalToConstant: 22).isActive = true
        let input = NSStackView(views: [icon, nameField]); input.spacing = 12
        context.font = .systemFont(ofSize: 12); context.textColor = .secondaryLabelColor
        context.lineBreakMode = .byTruncatingMiddle
        context.setAccessibilityIdentifier("name-and-pin-context")
        context.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        message.font = .systemFont(ofSize: 11); message.textColor = .systemRed
        let hint = NSTextField(labelWithString: "↵   esc")
        hint.font = .monospacedSystemFont(ofSize: 10, weight: .regular); hint.textColor = .secondaryLabelColor
        let cancel = NSButton(title: L("Cancel"), target: self, action: #selector(cancelPicker))
        confirm.target = self; confirm.action = #selector(saveName)
        cancel.bezelStyle = .rounded; confirm.bezelStyle = .rounded
        let footer = NSStackView(views: [hint, NSView(), cancel, confirm]); footer.spacing = 8
        for view in [header, input, context, message, footer] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18), header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 12), header.heightAnchor.constraint(equalToConstant: 24),
            input.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20), input.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            input.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10), input.heightAnchor.constraint(equalToConstant: 36),
            context.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20), context.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            context.topAnchor.constraint(equalTo: input.bottomAnchor, constant: 10),
            message.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20), message.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            message.topAnchor.constraint(equalTo: context.bottomAnchor, constant: 8), message.bottomAnchor.constraint(lessThanOrEqualTo: footer.topAnchor, constant: -8),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18), footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14), footer.heightAnchor.constraint(equalToConstant: 28)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    func setMessage(_ text: String?) { message.stringValue = text ?? "" }
    func setItem(progress: String, context: String, hasNext: Bool) {
        self.progress.stringValue = progress; self.context.stringValue = context
        confirm.title = hasNext ? L("Save and next") : L("Pin with name")
    }
    @objc private func cancelPicker() { onCancel?() }
    @objc private func saveName() { onConfirm?() }
}
