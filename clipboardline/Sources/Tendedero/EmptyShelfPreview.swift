import AppKit

/// Keeps the existing preview window available for undo after its final item
/// is taken down. No deleted content or stale copy/pin controls remain active.
@MainActor final class EmptyShelfPreview: NSObject, NSWindowDelegate {
    let window: ActionPreviewPanel
    var onClose: (() -> Void)?
    var onKey: ((NSEvent) -> Bool)?
    var onUndo: (() -> Void)?
    let message: NSTextField
    init(window: ActionPreviewPanel, keyboardBindings: KeyboardBindings, message: String, undoAction: KeyboardAction = .undoRemoveFromLine) {
        self.message = NSTextField(labelWithString: message)
        self.window = makePreviewPanel(size: NSSize(width: max(360, window.frame.width), height: max(240, window.frame.height)), reusing: window)
        super.init()
        window.delegate = self
        window.onKey = { [weak self] event in
            guard let self else { return false }
            let action = keyboardBindings.action(for: event, in: .imagePreview)
            if action == .close || action == .preview { self.window.close(); return true }
            return self.onKey?(event) ?? false
        }
        let surface = NSVisualEffectView()
        surface.material = .hudWindow; surface.blendingMode = .behindWindow; surface.state = .active
        surface.wantsLayer = true; surface.layer?.cornerRadius = 20; surface.layer?.masksToBounds = true
        let label = self.message
        label.font = .systemFont(ofSize: 18, weight: .medium)
        let undo = NSButton(title: undoAction.title + " · " + keyboardBindings.title(undoAction), target: self, action: #selector(undoRemoval))
        let close = NSButton(title: L("Close preview"), target: self, action: #selector(closePreview))
        let stack = NSStackView(views: [label, undo, close])
        stack.orientation = .vertical; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: surface.centerXAnchor), stack.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: surface.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(lessThanOrEqualTo: surface.trailingAnchor, constant: -20)])
        surface.setAccessibilityIdentifier(undoAction == .undoTrash ? "empty-library-preview" : "empty-shelf-preview")
        window.contentView = surface
    }
    @objc private func undoRemoval() { onUndo?() }
    @objc private func closePreview() { window.close() }
    func windowWillClose(_ notification: Notification) { onClose?() }
}
