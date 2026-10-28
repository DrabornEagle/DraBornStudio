import AppKit

private final class ShortcutRecordingPanel: NSPanel {
    var onKey: ((NSEvent) -> Void)?
    override var canBecomeKey: Bool { true }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown { onKey?(event); return }
        super.sendEvent(event)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown { onKey?(event); return true }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class ShortcutRecorder: NSObject, NSWindowDelegate {
    let window: NSPanel
    private let label = NSTextField(labelWithString: L("Press a key with Control or Command"))
    private let saveButton = NSButton(title: L("Save shortcut"), target: nil, action: nil)
    private var candidate: KeyShortcut?
    private var finished = false
    private var suspension: HotKey.Suspension?
    private let allowsPlain: Bool
    var onFinish: ((KeyShortcut?) -> Void)?
    var onRestoreFailure: (() -> Void)?

    init(allowPlain: Bool = false) {
        allowsPlain = allowPlain
        window = ShortcutRecordingPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 150),
            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        window.title = allowPlain ? L("Set shortcut") : L("Set copy-latest shortcut")
        if allowPlain { label.stringValue = L("Press a key, then click Save shortcut") }
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.level = .floating
        window.delegate = self
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 150))
        (window as? ShortcutRecordingPanel)?.onKey = { [weak self] in self?.receive($0) }
        label.frame = NSRect(x: 24, y: 85, width: 392, height: 28)
        root.addSubview(label)
        saveButton.frame = NSRect(x: 270, y: 25, width: 145, height: 32)
        saveButton.target = self; saveButton.action = #selector(save); saveButton.isEnabled = false
        root.addSubview(saveButton)
        let cancel = NSButton(title: L("Cancel"), target: self, action: #selector(cancel))
        cancel.frame = NSRect(x: 170, y: 25, width: 90, height: 32)
        root.addSubview(cancel)
        window.contentView = root
        window.center()
    }
    func beginRecording() {
        guard !finished else { return }
        if suspension == nil { suspension = HotKey.suspendAll(onRestoreFailure: onRestoreFailure) }
    }
    func show() {
        guard !finished else { return }
        beginRecording()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.contentView)
    }
    private func receive(_ event: NSEvent) {
        if event.keyCode == 53 { finish(nil); return }
        if !allowsPlain && event.keyCode == 36 && event.modifierFlags.intersection([.control, .option, .command, .shift]).isEmpty {
            if let candidate { finish(candidate) }; return
        }
        candidate = KeyShortcut.capture(event, allowPlain: allowsPlain)
        label.stringValue = candidate?.title ?? (allowsPlain ? L("Press a key, then click Save shortcut") : L("Use Control or Command with a key"))
        saveButton.isEnabled = candidate != nil
    }
    @objc private func cancel() { finish(nil) }
    @objc private func save() { if let candidate { finish(candidate) } }
    private func finish(_ value: KeyShortcut?) {
        guard !finished else { return }; finished = true
        window.close(); suspension?.resume(); suspension = nil; onFinish?(value)
    }
    func windowDidResignKey(_ notification: Notification) { finish(nil) }
    func windowWillClose(_ notification: Notification) { finish(nil) }
}
