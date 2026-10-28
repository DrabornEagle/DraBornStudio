import AppKit

/// Captures IDs before opening: later selection changes cannot broaden a batch.
/// Enter commits pin + membership in one store transaction; Escape changes nothing.
@MainActor final class PinFolderPicker: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    struct Choice { let id: UUID?; let title: String; let depth: Int }
    static let recentFoldersKey = "recentPinFolderIDsV1"
    let window: ActionPreviewPanel
    let table: NSTableView
    let searchField: PickerSearchField
    private(set) var choices = [Choice]()
    private(set) var searchQuery = ""
    private(set) var creating = false
    private var allChoices = [Choice]()
    private var searchableTitles = [UUID: String]()
    private let store: LibraryStore
    let ids: [UUID]
    private let surface: KeyboardPickerSurface
    private var queryBeforeCreating = ""
    var onClose: (() -> Void)?

    init(store: LibraryStore, ids: [UUID]) throws {
        let capturedIDs = Array(Set(ids)), table = NSTableView(), searchField = PickerSearchField(placeholder: L("Search folders…"))
        self.store = store; self.ids = capturedIDs; self.table = table; self.searchField = searchField
        surface = KeyboardPickerSurface(heading: String(format: L("Pin %d items to a folder"), capturedIDs.count), searchField: searchField, table: table)
        window = ActionPreviewPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        window.title = L("Pin to folder…"); window.isReleasedWhenClosed = false
        window.delegate = self; window.level = .floating; window.hidesOnDeactivate = false
        window.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.contentView = surface; window.isMovableByWindowBackground = true
        searchField.delegate = self
        table.dataSource = self; table.delegate = self; table.target = self; table.doubleAction = #selector(confirm)
        table.setAccessibilityLabel(L("Add to folder"))
        surface.onClose = { [weak self] in self?.cancel() }
        let create = NSButton(title: L("New folder"), target: self, action: #selector(newFolder))
        create.keyEquivalent = "n"; create.keyEquivalentModifierMask = .command
        let save = NSButton(title: L("Pin favorite"), target: self, action: #selector(confirm))
        surface.installFooter(action: create, confirm: save)
        try reload()
        window.onKey = { [weak self] in self?.handle($0) ?? false }
    }
    private func reload(selecting id: UUID? = nil) throws {
        let folders = try store.collections()
        let titles = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.name) })
        searchableTitles = Dictionary(uniqueKeysWithValues: folders.map { folder in
            (folder.id, [folder.parentID.flatMap { titles[$0] }, folder.name].compactMap { $0 }.joined(separator: " / "))
        })
        allChoices = folders.filter { $0.parentID == nil }.flatMap { parent in
            [Choice(id: parent.id, title: parent.name, depth: 0)] + folders.filter { $0.parentID == parent.id }.map { Choice(id: $0.id, title: $0.name, depth: 1) }
        }
        let recent = (store.defaults.stringArray(forKey: Self.recentFoldersKey) ?? []).compactMap(UUID.init(uuidString:))
        let rank = Dictionary(recent.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        allChoices = allChoices.enumerated().sorted { lhs, rhs in
            let left = lhs.element.id.flatMap { rank[$0] } ?? Int.max
            let right = rhs.element.id.flatMap { rank[$0] } ?? Int.max
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
        allChoices.append(Choice(id: nil, title: L("Pin without folder"), depth: 0))
        applySearch(selecting: id)
    }
    func setSearchQuery(_ query: String) {
        searchQuery = query; if searchField.stringValue != query { searchField.stringValue = query }
        applySearch()
    }
    private func applySearch(selecting id: UUID? = nil) {
        let terms = searchQuery.keyboardSearchFolded.split(whereSeparator: \.isWhitespace).map(String.init)
        choices = allChoices.filter { choice in
            let title = choice.id.flatMap { searchableTitles[$0] } ?? choice.title
            return terms.allSatisfy { title.keyboardSearchFolded.contains($0) }
        }
        table.reloadData()
        if !choices.isEmpty {
            let row = id.flatMap { id in choices.firstIndex { $0.id == id } } ?? 0
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); table.scrollRowToVisible(row)
        } else { table.deselectAll(nil) }
        surface.setEmpty(choices.isEmpty ? L("No matching folders") : nil)
        surface.setCount(choices.count)
        surface.setMessage(nil)
    }
    func show(relativeTo parent: NSWindow?) {
        surface.show(window, relativeTo: parent)
        window.makeFirstResponder(searchField)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { choices.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard choices.indices.contains(row) else { return nil }
        let choice = choices[row]
        return KeyboardPickerSurface.row(title: choice.id.flatMap { searchableTitles[$0] } ?? choice.title, symbol: choice.id == nil ? "pin" : "folder")
    }
    @discardableResult func handle(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command, event.keyCode == 45 { newFolder(); return true }
        if modifiers == .command, event.keyCode == 3 { window.makeFirstResponder(searchField); return true }
        guard modifiers.isEmpty else { return false }
        if event.keyCode == 53 { cancel(); return true }
        if event.keyCode == 36 || event.keyCode == 76 { if creating { createFolder() } else { confirm() }; return true }
        if !creating, event.keyCode == 125 || event.keyCode == 126 {
            moveSelection(event.keyCode == 126 ? -1 : 1); return true
        }
        // Clicking a result must not strand subsequent typing in the table.
        if window.firstResponder === table, let text = event.characters, !text.isEmpty,
           text.rangeOfCharacter(from: .controlCharacters) == nil {
            window.makeFirstResponder(searchField)
            searchField.currentEditor()?.interpretKeyEvents([event]); return true
        }
        return false
    }
    private func moveSelection(_ delta: Int) {
        guard !choices.isEmpty else { return }
        let row = max(0, min(choices.count - 1, max(0, table.selectedRow) + delta))
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); table.scrollRowToVisible(row)
    }
    func controlTextDidChange(_ notification: Notification) {
        if !creating { setSearchQuery(searchField.stringValue) }
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)): if !creating { moveSelection(1); return true }
        case #selector(NSResponder.moveUp(_:)): if !creating { moveSelection(-1); return true }
        case #selector(NSResponder.insertNewline(_:)): if creating { createFolder() } else { confirm() }; return true
        case #selector(NSResponder.cancelOperation(_:)): cancel(); return true
        default: break
        }
        return false
    }
    @objc private func confirm() {
        if creating { createFolder(); return }
        guard !ids.isEmpty, choices.indices.contains(table.selectedRow) else { return }
        let folder = choices[table.selectedRow].id
        do {
            try store.pin(ids, to: folder)
            if let folder {
                let value = folder.uuidString
                let previous = store.defaults.stringArray(forKey: Self.recentFoldersKey) ?? []
                store.defaults.set(Array(([value] + previous.filter { $0 != value }).prefix(8)), forKey: Self.recentFoldersKey)
            }
            window.close()
        } catch { surface.setMessage(error.localizedDescription) }
    }
    @objc private func newFolder() {
        guard !creating else { return }
        queryBeforeCreating = searchQuery; creating = true
        searchField.placeholderString = L("New folder"); surface.setMessage(L("New folder"), error: false)
        window.makeFirstResponder(searchField); searchField.selectText(nil)
    }
    private func createFolder() {
        do {
            let id = try store.createCollection(searchField.stringValue)
            creating = false; searchQuery = ""; searchField.stringValue = ""; searchField.placeholderString = L("Search folders…")
            try reload(selecting: id); window.makeFirstResponder(searchField)
        } catch { surface.setMessage(error.localizedDescription) }
    }
    @objc private func cancel() {
        if creating {
            creating = false; searchField.placeholderString = L("Search folders…")
            setSearchQuery(queryBeforeCreating); window.makeFirstResponder(searchField)
        } else { window.close() }
    }
    func windowWillClose(_ notification: Notification) { window.parent?.removeChildWindow(window); onClose?() }
}

/// The same quiet native input and rounded search surface as the shelves.
@MainActor final class PickerSearchField: NSTextField {
    init(placeholder: String) {
        super.init(frame: .zero)
        font = .systemFont(ofSize: 20); isEditable = true; isSelectable = true
        isBordered = false; isBezeled = false; drawsBackground = false
        focusRingType = .none; usesSingleLineMode = true; cell?.isScrollable = true
        placeholderString = placeholder; setAccessibilityLabel(placeholder)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }
}

@MainActor final class KeyboardPickerSurface: NSVisualEffectView {
    private let message = NSTextField(labelWithString: "")
    private let count = NSTextField(labelWithString: "")
    private let empty = NSTextField(labelWithString: "")
    private let footer = NSStackView()
    var onClose: (() -> Void)?
    init(heading: String, searchField: NSTextField, table: NSTableView) {
        super.init(frame: .zero)
        material = .hudWindow; blendingMode = .withinWindow; state = .active
        wantsLayer = true; layer?.cornerRadius = 16; layer?.masksToBounds = true
        let title = NSTextField(labelWithString: heading); title.font = .systemFont(ofSize: 11, weight: .semibold); title.textColor = .secondaryLabelColor
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: L("Close"))!, target: self, action: #selector(closePicker))
        close.isBordered = false; close.bezelStyle = .inline; close.setAccessibilityLabel(L("Close"))
        close.widthAnchor.constraint(equalToConstant: 24).isActive = true
        count.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular); count.textColor = .secondaryLabelColor
        let header = NSStackView(views: [title, NSView(), count, close]); header.spacing = 10
        let icon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
        icon.contentTintColor = .secondaryLabelColor; icon.widthAnchor.constraint(equalToConstant: 22).isActive = true
        let search = NSStackView(views: [icon, searchField]); search.spacing = 12
        let column = NSTableColumn(identifier: .init("choice")); column.width = 456
        column.resizingMask = .autoresizingMask; table.addTableColumn(column); table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.headerView = nil; table.rowHeight = 36; table.style = .fullWidth
        table.allowsEmptySelection = false; table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        scroll.drawsBackground = false; scroll.borderType = .noBorder; scroll.autohidesScrollers = true
        let separator = NSBox(); separator.boxType = .separator
        message.font = .systemFont(ofSize: 11); message.lineBreakMode = .byTruncatingTail
        empty.font = .systemFont(ofSize: 13); empty.textColor = .secondaryLabelColor; empty.isHidden = true
        footer.spacing = 8; footer.orientation = .horizontal
        for view in [header, search, separator, scroll, empty, message, footer] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18), header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14), header.topAnchor.constraint(equalTo: topAnchor, constant: 12), header.heightAnchor.constraint(equalToConstant: 24),
            search.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20), search.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20), search.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 9), search.heightAnchor.constraint(equalToConstant: 32),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16), separator.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), scroll.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8), scroll.bottomAnchor.constraint(equalTo: message.topAnchor, constant: -8),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor), empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            message.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20), message.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20), message.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -6), message.heightAnchor.constraint(equalToConstant: 16),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18), footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18), footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14), footer.heightAnchor.constraint(equalToConstant: 28)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    func installFooter(action: NSButton?, confirm: NSButton) {
        let hint = NSTextField(labelWithString: "↑ ↓   ↵   esc"); hint.font = .monospacedSystemFont(ofSize: 10, weight: .regular); hint.textColor = .secondaryLabelColor
        footer.addArrangedSubview(hint); footer.addArrangedSubview(NSView())
        if let action { action.bezelStyle = .rounded; footer.addArrangedSubview(action) }
        confirm.bezelStyle = .rounded; footer.addArrangedSubview(confirm)
    }
    func setCount(_ value: Int) { count.stringValue = String(value) }
    func setEmpty(_ text: String?) { empty.stringValue = text ?? ""; empty.isHidden = text == nil }
    func setMessage(_ text: String?, error: Bool = true) { message.stringValue = text ?? ""; message.textColor = error ? .systemRed : .secondaryLabelColor }
    func show(_ window: NSWindow, relativeTo parent: NSWindow?) {
        let frame = parent?.screen?.visibleFrame ?? LinePanel.screenUnderPointer()?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 750)
        let size = NSSize(width: min(520, frame.width - 32), height: min(420, frame.height - 32))
        window.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height), display: false)
        parent?.addChildWindow(window, ordered: .above); window.makeKeyAndOrderFront(nil)
    }
    static func row(title: String, symbol: String) -> NSView {
        let label = NSTextField(labelWithString: title); label.font = .systemFont(ofSize: 13); label.lineBreakMode = .byTruncatingMiddle
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        icon.contentTintColor = .secondaryLabelColor; icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        let stack = NSStackView(views: [icon, label]); stack.spacing = 10; stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        return stack
    }
    @objc private func closePicker() { onClose?() }
}

/// Forgiving text matching for keyboard-driven UI lists only. The database's
/// folding and name-uniqueness rules deliberately keep their existing behavior.
extension String {
    var keyboardSearchFolded: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i").lowercased()
    }
}
