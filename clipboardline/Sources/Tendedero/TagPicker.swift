import AppKit

/// Adds one existing or newly typed tag to the captured selection in one batch.
/// The input remains a native editor, so text-editing shortcuts never affect items.
@MainActor final class TagPicker: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    struct Choice { let id: UUID?; let title: String; let isNew: Bool }
    let window: ActionPreviewPanel
    let table: NSTableView
    let searchField: PickerSearchField
    let ids: [UUID]
    private(set) var choices = [Choice]()
    private(set) var searchQuery = ""
    private let store: LibraryStore
    private let tags: [LibraryTag]
    private let surface: KeyboardPickerSurface
    var onClose: (() -> Void)?

    init(store: LibraryStore, ids: [UUID]) throws {
        let capturedIDs = Array(Set(ids)), table = NSTableView(), searchField = PickerSearchField(placeholder: L("Search tags…"))
        self.store = store; self.ids = capturedIDs; tags = try store.tags(); self.table = table; self.searchField = searchField
        surface = KeyboardPickerSurface(heading: String(format: L("Add tag to %d items"), capturedIDs.count), searchField: searchField, table: table)
        window = ActionPreviewPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        window.title = L("Add tag…"); window.isReleasedWhenClosed = false
        window.delegate = self; window.level = .floating; window.hidesOnDeactivate = false
        window.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.contentView = surface; window.isMovableByWindowBackground = true
        searchField.delegate = self
        table.dataSource = self; table.delegate = self; table.target = self; table.doubleAction = #selector(confirm)
        table.setAccessibilityLabel(L("Tags"))
        surface.onClose = { [weak self] in self?.window.close() }
        let save = NSButton(title: L("Add tag…"), target: self, action: #selector(confirm))
        surface.installFooter(action: nil, confirm: save)
        setSearchQuery("")
        window.onKey = { [weak self] in self?.handle($0) ?? false }
    }
    func setSearchQuery(_ query: String) {
        searchQuery = query; if searchField.stringValue != query { searchField.stringValue = query }
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "#")))
        let terms = name.keyboardSearchFolded.split(whereSeparator: \.isWhitespace).map(String.init)
        choices = tags.filter { tag in terms.allSatisfy { tag.name.keyboardSearchFolded.contains($0) } }.map { Choice(id: $0.id, title: $0.name, isNew: false) }
        if !name.isEmpty, name.count <= 64, name.rangeOfCharacter(from: .controlCharacters) == nil,
           !tags.contains(where: { $0.name.keyboardSearchFolded == name.keyboardSearchFolded }) {
            choices.append(Choice(id: nil, title: name, isNew: true))
        }
        table.reloadData()
        if choices.isEmpty { table.deselectAll(nil) }
        else { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false); table.scrollRowToVisible(0) }
        surface.setEmpty(choices.isEmpty ? L("No matching tags") : nil)
        surface.setCount(choices.count); surface.setMessage(nil)
    }
    func show(relativeTo parent: NSWindow?) { surface.show(window, relativeTo: parent); window.makeFirstResponder(searchField) }
    func numberOfRows(in tableView: NSTableView) -> Int { choices.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard choices.indices.contains(row) else { return nil }
        let choice = choices[row]
        return KeyboardPickerSurface.row(title: choice.isNew ? String(format: L("Create tag “%@”"), choice.title) : choice.title, symbol: choice.isNew ? "plus" : "number")
    }
    @discardableResult func handle(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command, event.keyCode == 3 { window.makeFirstResponder(searchField); return true }
        guard modifiers.isEmpty else { return false }
        if event.keyCode == 53 { window.close(); return true }
        if event.keyCode == 36 || event.keyCode == 76 { confirm(); return true }
        if event.keyCode == 125 || event.keyCode == 126 { moveSelection(event.keyCode == 126 ? -1 : 1); return true }
        if window.firstResponder === table, let text = event.characters, !text.isEmpty,
           text.rangeOfCharacter(from: .controlCharacters) == nil {
            window.makeFirstResponder(searchField); searchField.currentEditor()?.interpretKeyEvents([event]); return true
        }
        return false
    }
    private func moveSelection(_ delta: Int) {
        guard !choices.isEmpty else { return }
        let row = max(0, min(choices.count - 1, max(0, table.selectedRow) + delta))
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); table.scrollRowToVisible(row)
    }
    func controlTextDidChange(_ notification: Notification) { setSearchQuery(searchField.stringValue) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)): moveSelection(1); return true
        case #selector(NSResponder.moveUp(_:)): moveSelection(-1); return true
        case #selector(NSResponder.insertNewline(_:)): confirm(); return true
        case #selector(NSResponder.cancelOperation(_:)): window.close(); return true
        default: return false
        }
    }
    @objc private func confirm() {
        guard !ids.isEmpty, choices.indices.contains(table.selectedRow) else { return }
        do { try store.addTag(choices[table.selectedRow].title, to: ids); window.close() }
        catch { surface.setMessage(error.localizedDescription) }
    }
    func windowWillClose(_ notification: Notification) { window.parent?.removeChildWindow(window); onClose?() }
}
