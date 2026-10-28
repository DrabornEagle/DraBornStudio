import AppKit

/// A native, keyboard-first command list using the shelf search HUD's sizing,
/// plain field editor, typography and rounded material surface.
@MainActor final class CommandPalette: NSObject, NSWindowDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    struct Command {
        let id: String
        let title: String
        let subtitle: String
        let keyHint: String
        let systemImage: String
        let isEnabled: Bool
        let group: String
        let keywords: [String]
        let disabledReason: String
        let isActive: Bool

        init(id: String, title: String, subtitle: String = "", keyHint: String = "", systemImage: String = "command", isEnabled: Bool = true,
             group: String = "", keywords: [String] = [], disabledReason: String = "", isActive: Bool = false) {
            self.id = id; self.title = title; self.subtitle = subtitle
            self.keyHint = keyHint; self.systemImage = systemImage; self.isEnabled = isEnabled
            self.group = group; self.keywords = keywords
            self.disabledReason = disabledReason; self.isActive = isActive
        }
    }

    let window: ActionPreviewPanel
    let searchField = NSTextField(string: "")
    let table = NSTableView()
    private(set) var visibleCommands = [Command]()
    private(set) var query = ""
    private(set) var shouldRestoreParentFocus = true
    var selectedCommandID: String? {
        guard visibleCommands.indices.contains(table.selectedRow) else { return nil }
        return visibleCommands[table.selectedRow].id
    }
    var onClose: (() -> Void)?
    var onSearchContents: (() -> Void)? {
        didSet { searchContentsButton.isHidden = onSearchContents == nil }
    }
    private var commands: [Command]
    private let onExecute: (String) -> Void
    private let count = NSTextField(labelWithString: "")
    private let empty = NSTextField(labelWithString: "")
    private let scroll = NSScrollView()
    private let searchContentsButton = NSButton()
    private var listHeight: NSLayoutConstraint!
    private var executed = false

    init(commands: [Command], onExecute: @escaping (String) -> Void) {
        self.commands = commands; self.onExecute = onExecute
        window = ActionPreviewPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 465),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        window.title = L("Actions"); window.isReleasedWhenClosed = false; window.delegate = self
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.level = .floating; window.hidesOnDeactivate = false
        window.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        window.onKey = { [weak self] in self?.handle($0) ?? false }
        buildSurface()
        updateQuery("")
    }

    private func buildSurface() {
        let surface = NSVisualEffectView()
        surface.material = .hudWindow; surface.blendingMode = .behindWindow; surface.state = .active
        surface.wantsLayer = true; surface.layer?.cornerRadius = 16; surface.layer?.masksToBounds = true
        surface.setAccessibilityIdentifier("command-palette")
        let tint = PaletteTintView(); tint.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(tint)
        NSLayoutConstraint.activate([tint.topAnchor.constraint(equalTo: surface.topAnchor), tint.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: surface.leadingAnchor), tint.trailingAnchor.constraint(equalTo: surface.trailingAnchor)])
        window.contentView = surface
        let heading = NSTextField(labelWithString: L("Actions"))
        heading.font = .systemFont(ofSize: 10, weight: .semibold); heading.textColor = .controlAccentColor
        let modeIcon = NSImageView(image: NSImage(systemSymbolName: "command", accessibilityDescription: nil)!)
        modeIcon.symbolConfiguration = .init(pointSize: 10, weight: .semibold); modeIcon.contentTintColor = .controlAccentColor
        let badge = NSStackView(views: [modeIcon, heading]); badge.spacing = 4
        badge.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        badge.wantsLayer = true; badge.layer?.cornerRadius = 10
        badge.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        searchContentsButton.title = L("Search contents")
        searchContentsButton.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        searchContentsButton.imagePosition = .imageLeading
        searchContentsButton.font = .systemFont(ofSize: 11, weight: .medium)
        searchContentsButton.isBordered = false; searchContentsButton.bezelStyle = .inline
        searchContentsButton.contentTintColor = .secondaryLabelColor
        searchContentsButton.target = self; searchContentsButton.action = #selector(searchContents)
        searchContentsButton.toolTip = L("Search contents")
        searchContentsButton.setAccessibilityLabel(L("Search contents"))
        searchContentsButton.setAccessibilityIdentifier("command-palette-search-contents")
        searchContentsButton.isHidden = onSearchContents == nil
        count.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular); count.textColor = .secondaryLabelColor
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: L("Close"))!, target: self, action: #selector(closePalette))
        close.isBordered = false; close.bezelStyle = .inline; close.contentTintColor = .secondaryLabelColor
        close.setAccessibilityLabel(L("Close")); close.toolTip = L("Close")
        close.widthAnchor.constraint(equalToConstant: 24).isActive = true
        close.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let header = NSStackView(views: [badge, NSView(), searchContentsButton, count, close]); header.spacing = 10
        let icon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
        icon.symbolConfiguration = .init(pointSize: 20, weight: .regular); icon.contentTintColor = .secondaryLabelColor
        icon.widthAnchor.constraint(equalToConstant: 22).isActive = true
        searchField.font = .systemFont(ofSize: 20); searchField.textColor = .labelColor
        searchField.isEditable = true; searchField.isSelectable = true; searchField.usesSingleLineMode = true
        searchField.isBordered = false; searchField.isBezeled = false; searchField.drawsBackground = false
        searchField.focusRingType = .none; searchField.cell?.isScrollable = true
        searchField.placeholderString = L("Search actions…"); searchField.delegate = self
        searchField.setAccessibilityLabel(L("Search actions…")); searchField.setAccessibilityIdentifier("command-palette-search")
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let input = NSStackView(views: [icon, searchField]); input.spacing = 12
        let separator = NSBox(); separator.boxType = .separator
        let column = NSTableColumn(identifier: .init("command")); column.width = 550
        table.addTableColumn(column); table.headerView = nil; table.rowHeight = 54; table.intercellSpacing = NSSize(width: 0, height: 2)
        table.style = .fullWidth; table.selectionHighlightStyle = .regular; table.backgroundColor = .clear
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.allowsEmptySelection = true; table.allowsMultipleSelection = false
        table.dataSource = self; table.delegate = self; table.target = self; table.action = #selector(clickedCommand)
        table.setAccessibilityLabel(L("Actions")); table.setAccessibilityIdentifier("command-palette-results")
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.borderType = .noBorder; scroll.drawsBackground = false
        empty.stringValue = L("No matching actions"); empty.font = .systemFont(ofSize: 13); empty.textColor = .secondaryLabelColor
        empty.alignment = .center
        let footer = NSStackView(views: [keyHint("↑ ↓"), label(L("Browse results")), NSView(), keyHint("↵"), label(L("Run action")), keyHint("esc"), label(L("Close"))])
        footer.spacing = 6; footer.alignment = .centerY
        for view in [header, input, separator, scroll, empty, footer] { view.translatesAutoresizingMaskIntoConstraints = false; surface.addSubview(view) }
        listHeight = scroll.heightAnchor.constraint(equalToConstant: 328)
        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: 24), header.topAnchor.constraint(equalTo: surface.topAnchor, constant: 12), header.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 18), header.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -18),
            input.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10), input.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 20), input.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -20), input.heightAnchor.constraint(equalToConstant: 30),
            separator.topAnchor.constraint(equalTo: input.bottomAnchor, constant: 14), separator.leadingAnchor.constraint(equalTo: surface.leadingAnchor), separator.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 7), scroll.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 8), scroll.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -8), listHeight,
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor), empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor), empty.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 12), empty.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -12),
            footer.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 9), footer.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 18), footer.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -18), footer.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -12), footer.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    private func label(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title); label.font = .systemFont(ofSize: 10); label.textColor = .secondaryLabelColor
        label.setContentHuggingPriority(.required, for: .horizontal); return label
    }
    private func keyHint(_ title: String) -> NSView {
        let keycap = ShortcutKeycapView(title)
        NSLayoutConstraint.activate([
            keycap.widthAnchor.constraint(equalToConstant: keycap.intrinsicContentSize.width),
            keycap.heightAnchor.constraint(equalToConstant: 18)
        ])
        return keycap
    }

    func updateQuery(_ value: String) {
        query = value
        if searchField.stringValue != value { searchField.stringValue = value }
        let tokens = value.keyboardSearchFolded.split(whereSeparator: \.isWhitespace).map(String.init)
        let phrase = tokens.joined(separator: " ")
        let matches = commands.enumerated().compactMap { index, command -> (index: Int, command: Command, rank: Int)? in
            // Search only intentional, user-facing words. Internal action IDs
            // must not accidentally become aliases for unrelated commands.
            let text = ([command.title, command.subtitle, command.group] + command.keywords).joined(separator: " ").keyboardSearchFolded
            guard tokens.allSatisfy({ text.contains($0) }) else { return nil }
            return (index, command, tokens.isEmpty ? 0 : relevance(command, tokens: tokens, phrase: phrase))
        }
        // The unfiltered list keeps its curated order. For searches, prefer
        // exact titles and word starts over incidental substrings such as
        // "pen" inside "Open"; the original order resolves equal relevance.
        visibleCommands = tokens.isEmpty ? matches.map(\.command) : matches.sorted { $0.rank == $1.rank ? $0.index < $1.index : $0.rank < $1.rank }.map(\.command)
        table.reloadData()
        let first = visibleCommands.firstIndex(where: \.isEnabled)
        table.selectRowIndexes(first.map { IndexSet(integer: $0) } ?? [], byExtendingSelection: false)
        if let first { table.scrollRowToVisible(first) }
        count.stringValue = "\(visibleCommands.count)"
        empty.isHidden = !visibleCommands.isEmpty
    }

    private func relevance(_ command: Command, tokens: [String], phrase: String) -> Int {
        func normalized(_ value: String) -> String { value.keyboardSearchFolded.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        let title = normalized(command.title)
        if title == phrase { return 0 }
        if title.hasPrefix(phrase) { return 1 }
        let words = title.split(separator: " ")
        if tokens.allSatisfy({ token in words.contains(where: { $0.hasPrefix(token) }) }) { return 2 }
        if tokens.allSatisfy({ title.contains($0) }) { return 3 }
        let aliases = command.keywords.map(normalized)
        if aliases.contains(phrase) { return 4 }
        if aliases.contains(where: { $0.hasPrefix(phrase) }) { return 5 }
        let aliasWords = aliases.flatMap { $0.split(separator: " ") }
        if tokens.allSatisfy({ token in aliasWords.contains(where: { $0.hasPrefix(token) }) }) { return 6 }
        return 7
    }

    func show(relativeTo parent: NSWindow?) {
        executed = false; shouldRestoreParentFocus = true
        let screen = parent?.screen?.visibleFrame ?? LinePanel.screenUnderPointer()?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 750)
        // Keep the command panel steady while typing rather than resizing for
        // every filter. A compact screen gets a shorter scrollable result list.
        let availableHeight = min(465, screen.height - 32)
        listHeight.constant = max(44, availableHeight - 137)
        let width = min(600, screen.width - 32), height = listHeight.constant + 137
        let anchor = parent?.frame ?? screen
        let x = max(screen.minX + 16, min(screen.maxX - width - 16, anchor.midX - width / 2))
        let y = max(screen.minY + 16, min(screen.maxY - height - 16, anchor.midY - height / 2))
        window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
        parent?.addChildWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(searchField)
    }

    @discardableResult func handle(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
        switch event.keyCode {
        case 125: moveSelection(1)
        case 126: moveSelection(-1)
        case 36, 76: executeSelected()
        case 53: closePalette()
        default: return false
        }
        return true
    }
    func moveSelection(_ delta: Int) {
        guard delta != 0 else { return }
        let enabled = visibleCommands.indices.filter { visibleCommands[$0].isEnabled }
        guard !enabled.isEmpty else { return }
        let current = enabled.firstIndex(of: table.selectedRow) ?? (delta > 0 ? -1 : enabled.count)
        let target = enabled[max(0, min(enabled.count - 1, current + (delta < 0 ? -1 : 1)))]
        table.selectRowIndexes(IndexSet(integer: target), byExtendingSelection: false); table.scrollRowToVisible(target)
    }
    func executeSelected() {
        guard !executed, visibleCommands.indices.contains(table.selectedRow), visibleCommands[table.selectedRow].isEnabled else { return }
        let id = visibleCommands[table.selectedRow].id, execute = onExecute
        executed = true
        // Close first so an action can safely open a preview, settings or a
        // folder picker without a stale palette recapturing native focus.
        window.close(); execute(id)
    }
    @objc private func clickedCommand() {
        let row = table.clickedRow
        guard visibleCommands.indices.contains(row), visibleCommands[row].isEnabled else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); executeSelected()
    }
    @objc private func searchContents() {
        guard !executed, let search = onSearchContents else { return }
        executed = true
        window.close(); search()
    }
    @objc private func closePalette() { executed = true; window.close() }
    func controlTextDidChange(_ notification: Notification) { updateQuery(searchField.stringValue) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)): moveSelection(1)
        case #selector(NSResponder.moveUp(_:)): moveSelection(-1)
        case #selector(NSResponder.insertNewline(_:)): executeSelected()
        case #selector(NSResponder.cancelOperation(_:)): closePalette()
        default: return false
        }
        return true
    }
    func numberOfRows(in tableView: NSTableView) -> Int { visibleCommands.count }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { visibleCommands.indices.contains(row) && visibleCommands[row].isEnabled }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { PaletteRowView() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard visibleCommands.indices.contains(row) else { return nil }
        let command = visibleCommands[row]
        let icon = NSImageView(image: NSImage(systemSymbolName: command.systemImage, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor; icon.symbolConfiguration = .init(pointSize: 16, weight: .regular)
        icon.widthAnchor.constraint(equalToConstant: 22).isActive = true
        let title = NSTextField(labelWithString: command.title)
        title.font = .systemFont(ofSize: 13, weight: .medium); title.lineBreakMode = .byTruncatingTail
        let labels = NSStackView(views: [title]); labels.orientation = .vertical; labels.alignment = .leading; labels.spacing = 3
        let detail = !command.isEnabled && !command.disabledReason.isEmpty ? command.disabledReason : command.subtitle
        let description = [command.group, detail].filter { !$0.isEmpty }.joined(separator: " · ")
        if !description.isEmpty {
            let subtitle = NSTextField(labelWithString: description)
            subtitle.font = .systemFont(ofSize: 11); subtitle.textColor = .secondaryLabelColor; subtitle.lineBreakMode = .byTruncatingTail
            labels.addArrangedSubview(subtitle)
        }
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let rowView = NSStackView(views: [icon, labels, NSView()])
        rowView.alignment = .centerY
        if command.isActive {
            let active = NSImageView(image: NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)!)
            active.symbolConfiguration = .init(pointSize: 11, weight: .semibold); active.contentTintColor = .controlAccentColor
            active.widthAnchor.constraint(equalToConstant: 18).isActive = true
            rowView.addArrangedSubview(active)
        }
        if !command.keyHint.isEmpty { rowView.addArrangedSubview(keyHint(command.keyHint)) }
        rowView.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 10); rowView.spacing = 10
        rowView.alphaValue = command.isEnabled ? 1 : 0.65
        rowView.toolTip = [command.title, description, command.keyHint].filter { !$0.isEmpty }.joined(separator: "\n")
        rowView.setAccessibilityElement(true)
        rowView.setAccessibilityLabel([command.title, description, command.keyHint].filter { !$0.isEmpty }.joined(separator: ", "))
        rowView.setAccessibilityEnabled(command.isEnabled)
        rowView.setAccessibilityValue(command.isActive ? "1" : "0")
        rowView.setAccessibilityIdentifier("command-" + command.id)
        return rowView
    }
    func windowWillClose(_ notification: Notification) {
        executed = true
        window.makeFirstResponder(nil); window.parent?.removeChildWindow(window); onClose?()
    }
    func windowDidResignKey(_ notification: Notification) {
        guard window.isVisible, !executed else { return }
        // Clicking another item, sidebar or app ends this captured action
        // context. Do not reclaim focus from the surface the user just chose.
        shouldRestoreParentFocus = false; executed = true; window.close()
    }
}

/// Keep the result highlight in the same quiet, rounded visual language as
/// the shelf search HUD while NSTableView retains selection accessibility.
private final class PaletteRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 8, yRadius: 8).fill()
    }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

/// Draw dynamic AppKit colors whenever the effective appearance changes.
private final class PaletteTintView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.withAlphaComponent(0.88).setFill(); bounds.fill()
        NSColor.labelColor.withAlphaComponent(0.12).setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 16, yRadius: 16)
        border.lineWidth = 1; border.stroke()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}
