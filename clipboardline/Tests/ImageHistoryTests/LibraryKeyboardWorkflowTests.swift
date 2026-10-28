import AppKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor private final class LibraryWorkflowButton: NSButton {
    override var acceptsFirstResponder: Bool { true }
    var activations = 0
    init() {
        super.init(frame: NSRect(x: 10, y: 10, width: 100, height: 28))
        title = "Synthetic action"; target = self; action = #selector(activate)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func activate() { activations += 1 }
}

/// Real AppKit windows, delegates and preview key routes, on synthetic records
/// and a private pasteboard. These tests do not post global events or drive any
/// other application; public desktop/OS-paste acceptance remains separate.
@MainActor final class LibraryKeyboardWorkflowTests: HistoryTestCase {
    private func wait(_ message: String, _ predicate: () -> Bool) {
        let deadline = Date().addingTimeInterval(6)
        while !predicate() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
        XCTAssertTrue(predicate(), message)
    }
    private func key(_ code: UInt16, _ text: String = "", _ flags: NSEvent.ModifierFlags = [], in window: NSWindow? = nil) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: window?.windowNumber ?? 0, context: nil, characters: text,
            charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
    }
    private func library(_ f: SyntheticFixture, kinds: [LibraryKind]) throws -> (LibraryStore, [UUID]) {
        f.date = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date }, moveToTrash: fixtureTrash(f.folder))
        var ids = [UUID]()
        // The caller supplies newest-first kinds; actual captures happen in
        // chronological order through the production Store methods.
        for (index, kind) in kinds.enumerated().reversed() {
            let record: LibraryRecord
            switch kind {
            case .image: record = try store.captureImage(f.image(name: "Keyboard image \(index).png"))
            case .text: record = try XCTUnwrap(store.captureText("Synthetic keyboard note \(index)"))
            case .link: record = try store.captureLink(try XCTUnwrap(URL(string: "https://example.com/keyboard-workflow/\(index)")))
            }
            try store.retain([record.id]); ids.insert(record.id, at: 0); f.date += 1
        }
        return (store, ids)
    }
    private func board() -> NSPasteboard { NSPasteboard(name: .init("library-keyboard-workflow-\(UUID())")) }
    private func controller(_ f: SyntheticFixture, _ store: LibraryStore, _ board: NSPasteboard) -> LibraryWindowController {
        LibraryWindowController(store: store,
            line: Line(defaults: f.defaults, inbox: f.inbox, breeze: false, library: store), copyPasteboard: board)
    }
    private func close(_ controller: LibraryWindowController) {
        if let window = controller.window, let sheet = window.attachedSheet {
            window.endSheet(sheet, returnCode: .cancel); sheet.orderOut(nil)
        }
        controller.dismissPreviews()
        controller.window?.makeFirstResponder(nil)
        controller.window?.close(); controller.window?.contentViewController = nil
        _ = controller.model.suspendUpdates()
    }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func isEditing(_ field: NSTextField, in window: NSWindow) -> Bool {
        window.firstResponder === field || (field.currentEditor() != nil && window.firstResponder === field.currentEditor())
    }
    private func open(_ controller: LibraryWindowController, count: Int) throws -> LibraryNativeWindow {
        let window = try XCTUnwrap(controller.window as? LibraryNativeWindow)
        controller.present()
        wait("Library opens with a native content focus and its first item selected") {
            window.contentView?.layoutSubtreeIfNeeded()
            return !controller.model.loading && controller.model.ids.count == count &&
                controller.model.focusedID == controller.model.ids.first &&
                (window.firstResponder is NSCollectionView || window.firstResponder is NSTableView)
        }
        return window
    }
    func testNativeSearchPendingQueryDownReturnAndEscapeEnterLatestResults() throws {
        _ = NSApplication.shared
        for entry in [UInt16(125), 36, 53] {
            let f = try SyntheticFixture(); defer { f.cleanup() }
            let (store, ids) = try library(f, kinds: [.text, .text, .text])
            try store.update(ids[1]) { $0.title = "Needle result" }
            let board = board(); defer { board.releaseGlobally() }
            let controller = controller(f, store, board); defer { close(controller) }
            let window = try open(controller, count: 3), model = controller.model
            XCTAssertTrue(model.select(ids[2]))
            controller.focusKeyboardPane(.search)
            let field = controller.toolbarController.searchField
            wait("Native search field owns its field editor") { self.isEditing(field, in: window) }
            field.stringValue = "Needle"
            // Invoke the real NSSearchField delegate before the debounce fires.
            field.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
            XCTAssertEqual(model.search, "Needle"); XCTAssertEqual(model.query.search, "")
            window.sendEvent(key(entry, entry == 36 ? "\r" : "", in: window))
            wait("Search entry commits the pending query and focuses its first real result") {
                !model.loading && model.query.search == "Needle" && model.ids == [ids[1]] &&
                    model.focusedID == ids[1] && window.firstResponder is NSCollectionView
            }
            XCTAssertEqual(model.selectedIDs, [ids[1]])
            XCTAssertEqual(field.stringValue, "Needle", "Leaving search preserves its query")
            XCTAssertTrue(window.performKeyEquivalent(with: key(0, "a", [.command], in: window)))
            XCTAssertEqual(model.selectedIDs, [ids[1]], "The very next shortcut targets results, not the old field editor")
        }
    }
    func testPaneLetterRemapLeavesNativeEditorsAloneButFunctionKeysStillCycle() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let (store, _) = try library(f, kinds: [.text])
        let board = board(); defer { board.releaseGlobally() }
        let controller = controller(f, store, board); defer { close(controller) }
        let window = try open(controller, count: 1), model = controller.model
        controller.focusKeyboardPane(.search)
        let field = controller.toolbarController.searchField
        wait("Search is editing") { self.isEditing(field, in: window) }
        try model.keyboardBindings.set([KeyShortcut(keyCode: 38, modifiers: 0, keyLabel: "J"),
            KeyShortcut(keyCode: 97, modifiers: 0, keyLabel: "F6")], for: .focusNextPane)
        XCTAssertFalse(model.handleKey(key(38, "j", in: window), editing: true))
        XCTAssertTrue(isEditing(field, in: window)); XCTAssertEqual(controller.keyboardPane, .search)
        window.sendEvent(key(38, "j", in: window))
        XCTAssertTrue(isEditing(field, in: window), "A remapped ordinary character stays in the native editor")
        XCTAssertTrue(window.performKeyEquivalent(with: key(97, in: window)))
        XCTAssertEqual(controller.keyboardPane, .sidebar)
        XCTAssertTrue(window.performKeyEquivalent(with: key(97, in: window)))
        wait("F6 returns from sidebar to content") { window.firstResponder is NSCollectionView }
        XCTAssertEqual(controller.keyboardPane, .content)
        try model.keyboardBindings.reset(.focusNextPane)
        XCTAssertTrue(window.performKeyEquivalent(with: key(48, "\t", [.control], in: window)))
        wait("Control-Tab focuses the inspected record") { controller.keyboardPane == .inspector }
        XCTAssertTrue(window.performKeyEquivalent(with: key(97, "", [.shift], in: window)))
        wait("Shift-F6 returns to content") { window.firstResponder is NSCollectionView }
    }
    func testNewNoteAndNewFolderKeysUseNativeInspectorAndSheet() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let (store, original) = try library(f, kinds: [.image])
        let board = board(); defer { board.releaseGlobally() }
        let controller = controller(f, store, board); defer { close(controller) }
        let window = try open(controller, count: 1), model = controller.model
        XCTAssertTrue(window.performKeyEquivalent(with: key(45, "n", [.command], in: window)))
        wait("New note is selected and its inspector owns focus") {
            window.contentView?.layoutSubtreeIfNeeded()
            return !model.loading && model.ids.count == 1 && model.query.kind == .text &&
                model.focusedID != original.first && controller.keyboardPane == .inspector
        }
        let note = try XCTUnwrap(model.focusedID)
        XCTAssertEqual(try store.item(note)?.kind, .text); XCTAssertEqual(try store.item(note)?.text, "")
        XCTAssertNotNil(try store.item(note)?.retainedAt)
        XCTAssertTrue(window.performKeyEquivalent(with: key(45, "n", [.command, .shift], in: window)))
        wait("New folder uses a native sheet") { window.attachedSheet != nil }
        let sheet = try XCTUnwrap(window.attachedSheet), root = try XCTUnwrap(sheet.contentView)
        let field = try XCTUnwrap(descendants(root).compactMap { $0 as? NSTextField }.first { $0.isEditable })
        XCTAssertTrue(sheet.makeFirstResponder(field)); field.stringValue = "Keyboard-created folder"
        field.currentEditor()?.string = field.stringValue
        let save = try XCTUnwrap(sheet.defaultButtonCell?.controlView as? NSButton)
        XCTAssertEqual(save.title, L("Save")); XCTAssertTrue(save.isEnabled)
        // AppKit consumes Return into its native defaultButtonCell when the sheet is realized.
        XCTAssertTrue(sheet.defaultButtonCell === save.cell)
        let cancel = try XCTUnwrap(descendants(root).compactMap { $0 as? NSButton }.first { $0.title == L("Cancel") })
        XCTAssertEqual(cancel.keyEquivalent, "\u{1b}", "The native prompt must explicitly support Escape")
        // A headless XCTest application cannot make this native alert sheet
        // key. Activate its real default control without a mouse here; physical
        // Return submission is separately verified in the real-app Cua flow.
        save.performClick(nil)
        wait("The native default action saves the folder and closes its sheet") {
            window.attachedSheet == nil && (try? store.collections().contains { $0.name == "Keyboard-created folder" }) == true
        }
        XCTAssertEqual(try store.item(note)?.text, "")
    }
    func testMarkedSearchCompositionKeepsEscapeInNativeEditorUntilCommitted() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let (store, ids) = try library(f, kinds: [.text])
        let board = board(); defer { board.releaseGlobally() }
        let model = LibraryModel(store: store, copyPasteboard: board)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 250), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 250))
        let field = LibrarySearchTextField(model: model), content = NSCollectionView()
        field.frame = NSRect(x: 12, y: 210, width: 500, height: 26)
        root.addSubview(field); root.addSubview(content); window.contentView = root
        defer { window.makeFirstResponder(nil); window.contentView = nil; window.close(); _ = model.suspendUpdates() }
        // The window remains hidden; only AppKit's actual field editor and
        // NSTextInputClient marked-text state participate in this IME guard.
        wait("IME fixture query is ready") { !model.loading && model.ids == ids }
        XCTAssertTrue(model.select(ids[0])); model.onContentFocus = { window.makeFirstResponder(content) }
        XCTAssertTrue(window.makeFirstResponder(field)); field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.setMarkedText("候", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        let query = model.query, focused = model.focusedID
        XCTAssertFalse(model.handleKey(key(53, "\u{1b}", in: window), editing: true))
        XCTAssertTrue(window.firstResponder === editor); XCTAssertTrue(editor.hasMarkedText())
        XCTAssertEqual(model.query, query); XCTAssertEqual(model.focusedID, focused)
        XCTAssertFalse(model.contentFocusPending)
        editor.unmarkText(); XCTAssertFalse(editor.hasMarkedText())
        XCTAssertTrue(model.handleKey(key(53, "\u{1b}", in: window), editing: true))
        wait("After composition commits, Escape can return to content") { !model.loading && window.firstResponder === content }
    }
    func testMixedPreviewKeepsWindowAcrossGridPageAndBoundaryKeys() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let kinds: [LibraryKind] = (0..<12).map { [.image, .text, .link][$0 % 3] }
        let (store, ids) = try library(f, kinds: kinds)
        let board = board(); defer { board.releaseGlobally() }
        let model = LibraryModel(store: store, copyPasteboard: board); model.columns = 3
        let previews = LibraryPreviewController(model: model)
        defer { previews.close(); _ = model.suspendUpdates() }
        wait("Preview fixture query is ready") { !model.loading && model.ids == ids }
        XCTAssertTrue(model.select(ids[0])); previews.show(ids[0])
        let window = try XCTUnwrap(previews.window); XCTAssertNotNil(previews.image)
        let steps: [(UInt16, NSEvent.ModifierFlags, Int)] = [
            (124, [], 1), (124, [], 2), (125, [], 5), (124, [.option], 11),
            (123, [.command], 0), (124, [.command], 11), (123, [.option], 2), (126, [], 2), (123, [], 1)
        ]
        for (code, flags, index) in steps {
            window.sendEvent(key(code, "", flags, in: window))
            XCTAssertTrue(previews.window === window, "Content kinds reuse the same native window")
            XCTAssertEqual(previews.currentID, ids[index]); XCTAssertEqual(model.focusedID, ids[index])
            XCTAssertEqual(previews.image != nil, kinds[index] == .image)
            XCTAssertEqual(previews.text != nil, kinds[index] == .text)
            XCTAssertEqual(previews.link != nil, kinds[index] == .link)
        }
        XCTAssertNil(board.string(forType: .string))
    }
    func testPreviewTrashChoosesNeighborAndUndoReusesWindowForRestoredItem() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let (store, ids) = try library(f, kinds: [.image, .text, .link])
        let board = board(); defer { board.releaseGlobally() }
        let model = LibraryModel(store: store, copyPasteboard: board), previews = LibraryPreviewController(model: model)
        defer { previews.close(); _ = model.suspendUpdates() }
        wait("Preview query is ready") { !model.loading && model.ids == ids }
        XCTAssertTrue(model.select(ids[0])); previews.show(ids[0]); let window = try XCTUnwrap(previews.window)
        window.sendEvent(key(1, "s", in: window))
        wait("S trashes the previewed item and previews its next neighbor") {
            !model.loading && model.ids == Array(ids.dropFirst()) && previews.currentID == ids[1]
        }
        XCTAssertTrue(previews.window === window); XCTAssertNotNil(previews.text)
        XCTAssertEqual(model.focusedID, ids[1]); XCTAssertNotNil(try store.item(ids[0])?.deletedAt)
        window.sendEvent(key(51, "\u{7f}", in: window))
        wait("Backspace restores and previews the original item") {
            !model.loading && model.ids == ids && model.focusedID == ids[0] && previews.currentID == ids[0]
        }
        XCTAssertTrue(previews.window === window); XCTAssertNotNil(previews.image)
        XCTAssertEqual(model.selectedIDs, [ids[0]]); XCTAssertNil(try store.item(ids[0])?.deletedAt)
    }
    func testFinalPreviewTrashShowsEmptyStateInSameWindowAndBackspaceRestores() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let (store, ids) = try library(f, kinds: [.text])
        let board = board(); defer { board.releaseGlobally() }
        let model = LibraryModel(store: store, copyPasteboard: board), previews = LibraryPreviewController(model: model)
        defer { previews.close(); _ = model.suspendUpdates() }
        wait("Single result is ready") { !model.loading && model.ids == ids }
        XCTAssertTrue(model.select(ids[0])); previews.show(ids[0]); let window = try XCTUnwrap(previews.window)
        window.sendEvent(key(1, "s", in: window))
        wait("The final removal keeps an empty preview ready for undo") { !model.loading && model.ids.isEmpty && previews.empty != nil }
        XCTAssertTrue(previews.window === window); XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.contentView?.accessibilityIdentifier(), "empty-library-preview")
        XCTAssertNil(previews.currentID); XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertNotNil(try store.item(ids[0])?.retainedAt); XCTAssertNotNil(try store.item(ids[0])?.deletedAt)
        window.sendEvent(key(51, "\u{7f}", in: window))
        wait("Undo replaces the empty surface with the restored note") {
            !model.loading && model.ids == ids && previews.currentID == ids[0] && previews.empty == nil
        }
        XCTAssertTrue(previews.window === window); XCTAssertNotNil(previews.text)
        XCTAssertEqual(model.selectedIDs, [ids[0]]); XCTAssertNil(try store.item(ids[0])?.deletedAt)
    }
    func testPreviewReturnActivatesFocusedNativeButtonWithoutCopyingSelectedRecord() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let (store, ids) = try library(f, kinds: [.text])
        let board = board(); defer { board.releaseGlobally() }
        XCTAssertTrue(board.setString("private-pasteboard-sentinel", forType: .string))
        let model = LibraryModel(store: store, copyPasteboard: board), previews = LibraryPreviewController(model: model)
        defer { previews.close(); _ = model.suspendUpdates() }
        wait("Single result is ready") { !model.loading && model.ids == ids }
        XCTAssertTrue(model.select(ids[0])); previews.show(ids[0]); let window = try XCTUnwrap(previews.window)
        let button = LibraryWorkflowButton(); window.contentView?.addSubview(button)
        XCTAssertTrue(window.makeFirstResponder(button)); let count = board.changeCount
        let copiedBefore = try store.item(ids[0])?.lastCopiedAt
        window.sendEvent(key(36, "\r", in: window))
        XCTAssertEqual(button.activations, 1); XCTAssertTrue(window.firstResponder === button)
        XCTAssertEqual(board.changeCount, count); XCTAssertEqual(board.string(forType: .string), "private-pasteboard-sentinel")
        XCTAssertTrue(model.copiedIDs.isEmpty); XCTAssertEqual(try store.item(ids[0])?.lastCopiedAt, copiedBefore)
    }
    func testInvalidInspectorDraftBlocksEscapePaneCycleAndNewNoteUntilCorrected() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let (store, ids) = try library(f, kinds: [.text])
        let board = board(); defer { board.releaseGlobally() }
        let controller = controller(f, store, board), model = controller.model
        defer { model.draftText = "Corrected synthetic draft"; _ = model.flushEdits(); close(controller) }
        let window = try open(controller, count: 1)
        controller.focusKeyboardPane(.inspector)
        wait("Inspector owns an editable field") { controller.keyboardPane == .inspector }
        let editor = window.firstResponder
        let draft = String(repeating: "x", count: TextClipboardWatcher.maximumDataBytes + 1)
        model.draftText = draft
        XCTAssertTrue(window.performKeyEquivalent(with: key(53, "\u{1b}", in: window)))
        XCTAssertTrue(window.firstResponder === editor); XCTAssertEqual(controller.keyboardPane, .inspector)
        XCTAssertTrue(window.performKeyEquivalent(with: key(97, in: window)))
        XCTAssertTrue(window.firstResponder === editor); XCTAssertEqual(controller.keyboardPane, .inspector)
        XCTAssertTrue(window.performKeyEquivalent(with: key(45, "n", [.command], in: window)))
        XCTAssertEqual(try store.queryIDs(LibraryQuery()), ids)
        XCTAssertEqual(model.draftText, draft); XCTAssertEqual(try store.item(ids[0])?.text, "Synthetic keyboard note 0")
        model.draftText = "Corrected synthetic draft"; XCTAssertTrue(model.flushEdits())
        XCTAssertTrue(window.performKeyEquivalent(with: key(53, "\u{1b}", in: window)))
        wait("A corrected draft can return to content") { window.firstResponder is NSCollectionView }
        XCTAssertEqual(try store.item(ids[0])?.text, "Corrected synthetic draft")
    }
    func testInvalidPreviewDraftCannotEscapeOrNavigateAwayAndKeepsItsText() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let (store, ids) = try library(f, kinds: [.text, .text])
        let board = board(); defer { board.releaseGlobally() }
        let model = LibraryModel(store: store, copyPasteboard: board), previews = LibraryPreviewController(model: model)
        defer {
            if let text = previews.text { text.textView.string = "Corrected preview draft"; text.textDidChange(Notification(name: NSText.didChangeNotification)); _ = text.finishEditing() }
            previews.close(); _ = model.suspendUpdates()
        }
        wait("Text results are ready") { !model.loading && model.ids == ids }
        XCTAssertTrue(model.select(ids[0])); previews.show(ids[0])
        let text = try XCTUnwrap(previews.text), window = try XCTUnwrap(previews.window)
        text.beginEditing(); let draft = String(repeating: "y", count: TextClipboardWatcher.maximumDataBytes + 1)
        text.textView.string = draft; text.textDidChange(Notification(name: NSText.didChangeNotification, object: text.textView))
        window.sendEvent(key(53, "\u{1b}", in: window))
        XCTAssertTrue(text.isEditing); XCTAssertTrue(window.isVisible); XCTAssertTrue(window.firstResponder === text.textView)
        XCTAssertEqual(text.textView.string, draft); XCTAssertEqual(previews.currentID, ids[0])
        XCTAssertTrue(previews.performNavigation(.next), "The blocked navigation command is consumed without discarding the draft")
        XCTAssertTrue(previews.window === window)
        XCTAssertEqual(previews.currentID, ids[0]); XCTAssertEqual(try store.item(ids[0])?.text, "Synthetic keyboard note 0")
        text.textView.string = "Corrected preview draft"; text.textDidChange(Notification(name: NSText.didChangeNotification, object: text.textView))
        window.sendEvent(key(53, "\u{1b}", in: window)); XCTAssertFalse(text.isEditing)
        window.sendEvent(key(124, "", in: window)); XCTAssertEqual(previews.currentID, ids[1])
        XCTAssertEqual(try store.item(ids[0])?.text, "Corrected preview draft")
    }
    func testImageCommandZKeepsMarkupUndoPriorityAndBackspaceUndoesLibraryTrash() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let (store, ids) = try library(f, kinds: [.image, .text])
        let board = board(); defer { board.releaseGlobally() }
        let marks = ImageMarkupDocument(elements: [ImageMarkupElement(tool: .rectangle,
            points: [.init(x: 0.1, y: 0.1), .init(x: 0.8, y: 0.8)])])
        _ = try store.saveImageMarkup(ids[0], document: marks)
        try store.trashUndoably([ids[1]])
        let model = LibraryModel(store: store, copyPasteboard: board), previews = LibraryPreviewController(model: model)
        defer { previews.close(); _ = model.suspendUpdates() }
        wait("Only the live image is visible") { !model.loading && model.ids == [ids[0]] }
        XCTAssertTrue(model.select(ids[0])); previews.show(ids[0])
        let image = try XCTUnwrap(previews.image), window = try XCTUnwrap(previews.window)
        image.canvas.clearMarkup(); XCTAssertTrue(image.flushEdits()); XCTAssertTrue(image.canvas.canUndo)
        window.sendEvent(key(6, "z", [.command], in: window))
        XCTAssertEqual(image.document, marks); XCTAssertTrue(store.canUndoTrash)
        XCTAssertNotNil(try store.item(ids[1])?.deletedAt); XCTAssertEqual(previews.currentID, ids[0])
        window.sendEvent(key(51, "\u{7f}", in: window))
        wait("Backspace restores the trashed note through the Library undo route") {
            !model.loading && model.ids == ids && previews.currentID == ids[1]
        }
        XCTAssertTrue(previews.window === window); XCTAssertNil(try store.item(ids[1])?.deletedAt)
        XCTAssertEqual(try store.item(ids[0])?.imageMarkup, marks)
    }
}
