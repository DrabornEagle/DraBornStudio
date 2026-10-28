import AppKit
import Carbon
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class KeyboardSpeedTests: HistoryTestCase {
    private func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [], text: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
            isARepeat: false, keyCode: code)!
    }
    private func wait(_ predicate: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !predicate() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(predicate(), "Keyboard speed fixture did not settle")
    }
    private func line(_ f: SyntheticFixture, store: LibraryStore) -> Line {
        Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false,
            copyImage: { _ in }, copyText: { _ in }, library: store)
    }
    private func populate(_ f: SyntheticFixture, store: LibraryStore, count: Int) throws {
        for i in 0..<count {
            let image = try store.captureImage(f.image())
            try store.update(image.id) { $0.note = "speed keep image \(i)" }
            _ = try store.captureText("speed keep note \(i)")
            _ = try store.captureLink(try XCTUnwrap(URL(string: "https://example.com/speed/keep/\(i)")))
            f.date.addTimeInterval(1)
        }
    }
    private func displayed(_ line: Line, shelf: Shelf) -> [UUID] {
        switch shelf {
        case .images: line.displayItems.map(\.id)
        case .texts: line.texts.displayEntries.map(\.id)
        case .links: line.links.displayEntries.map(\.id)
        }
    }
    private func focused(_ line: Line) -> UUID? {
        switch line.activeShelf {
        case .images: line.focusedID
        case .texts: line.texts.focusedID
        case .links: line.links.focusedID
        }
    }
    private func scroll(_ line: Line, shelf: Shelf, to offset: CGFloat) {
        switch shelf {
        case .images: line.setScrollOffset(offset)
        case .texts: line.texts.scroll(-offset, width: line.viewportWidth)
        case .links: line.links.scroll(-offset, width: line.viewportWidth)
        }
    }

    func testPasteAndBrowserOpenDefaultsAreUnambiguousAndLegacyOverrideRemainsIntentional() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let bindings = KeyboardBindings(defaults: f.defaults)
        for context in KeyboardContext.allCases {
            XCTAssertEqual(bindings.action(for: key(36, flags: .command), in: context), .paste)
            XCTAssertEqual(bindings.action(for: key(76, flags: .command), in: context), .paste)
            XCTAssertEqual(bindings.action(for: key(36), in: context), .copy)
        }
        XCTAssertEqual(bindings.action(for: key(31, flags: .command, text: "o"), in: .linkPreview), .open)
        XCTAssertEqual(bindings.action(for: key(31, flags: .command, text: "o"), in: .library), .open)
        XCTAssertNil(bindings.action(for: key(31, flags: .command, text: "o"), in: .line))
        do {
            try bindings.set([KeyShortcut(keyCode: 36, modifiers: cmdKey, keyLabel: "↩")], for: .open)
            XCTAssertTrue(false, "New conflicting mappings must be rejected rather than silently replacing Paste")
        } catch let error as KeyboardBindings.Conflict { XCTAssertEqual(error.action, .paste) }
        // Existing preferences predate Paste. Their explicit mapping must win
        // over a newly introduced default until the user changes it themselves.
        let legacy = ["open": [KeyShortcut(keyCode: 36, modifiers: cmdKey, keyLabel: "↩")]]
        f.defaults.set(try JSONEncoder().encode(legacy), forKey: "contextKeyboardBindingsV1")
        XCTAssertEqual(bindings.action(for: key(36, flags: .command), in: .linkPreview), .open)
        XCTAssertEqual(bindings.action(for: key(36, flags: .command), in: .library), .open)
        XCTAssertEqual(bindings.action(for: key(36, flags: .command), in: .line), .paste)
        try bindings.reset(.open)
        XCTAssertEqual(bindings.action(for: key(36, flags: .command), in: .linkPreview), .paste)
    }

    func testTextEditorCommandReturnFinishesBeforeBrowseCommandReturnCanPaste() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let bindings = KeyboardBindings(defaults: f.defaults)
        let preview = TextPreview(text: "Original", keyboardBindings: bindings)
        defer { preview.window.close() }
        var pasted = 0, saved = [String]()
        preview.onSave = { saved.append($0); return true }
        preview.onKey = { event in
            guard bindings.action(for: event, in: .textPreview) == .paste else { return false }
            pasted += 1; return true
        }
        preview.beginEditing(); preview.textView.string = "Edited text"
        preview.textDidChange(Notification(name: NSText.didChangeNotification, object: preview.textView))
        XCTAssertFalse(preview.routeKey(key(18, text: "1")), "Digits remain text input while editing")
        XCTAssertFalse(preview.routeKey(key(1, text: "s")), "The shelf delete shortcut remains native text input")
        XCTAssertFalse(preview.routeKey(key(123)))
        XCTAssertTrue(preview.routeKey(key(36, flags: .command)))
        XCTAssertEqual(saved, ["Edited text"]); XCTAssertFalse(preview.isEditing)
        XCTAssertEqual(pasted, 0, "Finishing an edit cannot also paste into the previous app")
        XCTAssertTrue(preview.routeKey(key(36, flags: .command)))
        XCTAssertEqual(pasted, 1)
        try bindings.set([KeyShortcut(keyCode: 38, modifiers: cmdKey, keyLabel: "J")], for: .paste)
        XCTAssertFalse(preview.routeKey(key(36, flags: .command)), "A remapped Paste stops using Command-Return during browsing")
        XCTAssertTrue(preview.routeKey(key(38, flags: .command, text: "j")))
        XCTAssertEqual(pasted, 2)
        preview.beginEditing()
        XCTAssertTrue(preview.routeKey(key(76, flags: .command)), "Keypad Command-Enter still finishes the native editor")
        XCTAssertFalse(preview.isEditing); XCTAssertEqual(pasted, 2)
    }

    func testEditedPreviewOutsideSharedSearchResultsStillCopiesAndPastesDisplayedRecord() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        let edited = try XCTUnwrap(store.captureText("Synthetic original text"))
        let neighbor = try XCTUnwrap(store.captureText("Synthetic matching neighbor"))
        let unrelated = try XCTUnwrap(store.captureText("Unrelated untouched note"))
        var copiedTexts = [String]()
        let line = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false,
            copyImage: { _ in }, copyText: { copiedTexts.append($0) }, library: store)
        line.setPresentation(.all, requestFocus: false)
        line.beginShelfSearch(.texts); line.updateShelfSearch("synthetic", for: .texts)
        wait { !line.shelfSearchIsSearching && line.texts.displayEntries.count == 2 }
        line.finishShelfSearchEditing(.texts, selectFirst: false)
        let board = NSPasteboard(name: .init("local.clipboardline.edited-preview-paste.\(UUID())"))
        defer { board.releaseGlobally() }
        board.clearContents()
        let ownPID: pid_t = 900, targetPID: pid_t = 101, field = NSObject()
        var frontmost = targetPID, sent = [pid_t]()
        let environment = DirectPasteCoordinator.Environment(ownPID: ownPID,
            trusted: { true }, frontmostPID: { frontmost }, running: { $0 == targetPID },
            focusedField: { $0 == targetPID ? .init(identity: field, editable: true, secure: false) : nil },
            sameField: { $0.identity === $1.identity }, activate: { pid in frontmost = pid; return pid == targetPID },
            write: { ClipboardTransfer.write($0, to: board) }, sendPaste: { sent.append($0); return true },
            pause: { await Task.yield() })
        let coordinator = DirectPasteCoordinator(environment: environment)
        coordinator.captureTarget(); frontmost = ownPID
        let app = AppDelegate(line: line, watchesFiles: false, copyPasteboard: board, directPaste: coordinator)
        // No applicationDidFinishLaunching: this test creates no hotkeys,
        // clipboard watchers, status items or global event monitors.
        app.showTextPreview(edited.id)
        let preview = try XCTUnwrap(app.textPreview), panel = try XCTUnwrap(app.previewWindow)
        defer { coordinator.cancel(); panel.close() }
        let draft = "Edited draft moved outside the current query"
        preview.beginEditing(); preview.textView.string = draft
        preview.textDidChange(Notification(name: NSText.didChangeNotification, object: preview.textView))
        XCTAssertTrue(preview.routeKey(key(36, flags: .command)))
        XCTAssertFalse(preview.isEditing)
        XCTAssertTrue(sent.isEmpty, "The first Command-Return saves the editor without pasting")
        wait { !line.shelfSearchIsSearching && !line.texts.displayEntries.contains { $0.id == edited.id } }
        XCTAssertEqual(line.texts.displayEntries.map(\.id), [neighbor.id])
        XCTAssertFalse(app.previewSession?.hasCurrentItem ?? true)
        XCTAssertEqual(app.previewSession?.currentID, edited.id)
        XCTAssertTrue(app.previewWindow === panel); XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(preview.textView.string, draft)
        XCTAssertEqual(try store.item(edited.id)?.text, draft)

        XCTAssertTrue(preview.routeKey(key(8, flags: .command, text: "c")))
        XCTAssertEqual(copiedTexts, [draft], "Copy acts on the saved text still displayed, never its search-result neighbor")
        XCTAssertEqual(line.texts.copiedIDs, [edited.id])
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(preview.routeKey(key(36, flags: .command)))
        wait { sent.count == 1 }
        XCTAssertEqual(sent, [targetPID])
        XCTAssertEqual(board.string(forType: .string), draft)
        XCTAssertEqual(board.pasteboardItems?.count, 1)
        XCTAssertFalse(panel.isVisible); XCTAssertNil(app.previewSession)
        XCTAssertEqual(try store.item(neighbor.id)?.text, "Synthetic matching neighbor")
        XCTAssertEqual(try store.item(unrelated.id)?.text, "Unrelated untouched note")
    }

    func testQuickNumbersUseVisibleFilteredViewportInEveryShelfAndNeverCaptureSearchTyping() throws {
        let f = try SyntheticFixture(); defer { f.cleanup(); Layout.size = .medium; Layout.maximumRowHeight = .greatestFiniteMagnitude }
        Layout.size = .medium; Layout.maximumRowHeight = .greatestFiniteMagnitude
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(f, store: store, count: 15)
        // Newest raw history entries do not match the query. Numbering must be
        // relative to the displayed search results, never the original array.
        _ = try store.captureImage(f.image())
        _ = try store.captureText("Unrelated note")
        _ = try store.captureLink(try XCTUnwrap(URL(string: "https://example.com/unrelated")))
        let line = line(f, store: store); line.setPresentation(.all, requestFocus: false)
        line.setViewportWidth(720); line.beginShelfSearch(.images)
        line.updateShelfSearch("speed keep", for: .images)
        wait { !line.shelfSearchIsSearching && line.shelfSearchResultCount == 45 }
        let keyboard = LineKeyboard(line: line, onCopy: { _ in }, onPreview: { _ in }, onClose: {})
        XCTAssertTrue(line.quickSelectionIDs.isEmpty)
        XCTAssertFalse(keyboard.handle(key(18, text: "1")))
        line.finishShelfSearchEditing(.images, selectFirst: false)
        for shelf in Shelf.allCases {
            line.focusShelf(shelf, requestFocus: false)
            let ids = displayed(line, shelf: shelf)
            XCTAssertEqual(ids.count, 15)
            scroll(line, shelf: shelf, to: Layout.spacing * 3)
            XCTAssertEqual(line.quickSelectionIDs, Array(ids[3..<7]))
            XCTAssertEqual(line.quickSelectionNumber(ids[3], shelf: shelf), 1)
            XCTAssertNil(line.quickSelectionNumber(ids[2], shelf: shelf))
            XCTAssertTrue(keyboard.handle(key(20, text: "3")))
            XCTAssertEqual(focused(line), ids[5])
            XCTAssertEqual(line.activeIDs, [ids[5]])
            let before = focused(line)
            XCTAssertTrue(keyboard.handle(key(25, text: "9")))
            XCTAssertEqual(focused(line), before, "A number beyond the visible cards must not jump offscreen")
        }
        line.setViewportWidth(10000); line.focusShelf(.images, requestFocus: false); line.setScrollOffset(0)
        XCTAssertEqual(line.quickSelectionIDs, Array(line.displayItems.prefix(9).map(\.id)))
        XCTAssertTrue(keyboard.handle(key(25, text: "9")))
        XCTAssertEqual(line.focusedID, line.displayItems[8].id)
    }

    func testQuickNumbersDoNotCompressImageColumnsWhileAnItemIsFalling() throws {
        let f = try SyntheticFixture(); defer { f.cleanup(); Layout.size = .medium; Layout.maximumRowHeight = .greatestFiniteMagnitude }
        Layout.size = .medium; Layout.maximumRowHeight = .greatestFiniteMagnitude
        let line = f.line(); line.setViewportWidth(300)
        for _ in 0..<5 { line.hang(try f.image(owned: false), quietly: true) }
        let ids = line.displayItems.map(\.id)
        line.drop(ids[0], quietly: true)
        XCTAssertTrue(line.displayItems[0].falling)
        XCTAssertEqual(line.quickSelectionIDs, [ids[1]], "A falling card still occupies its visual column until its animation ends")
        XCTAssertEqual(line.quickSelectionNumber(ids[1], shelf: .images), 1)
        XCTAssertNil(line.quickSelectionNumber(ids[2], shelf: .images), "The next card center is outside this viewport")
    }

    func testSpeedActionsAndQuickSelectionRemapAndUseOnlyTheActiveRow() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(f, store: store, count: 3)
        let line = line(f, store: store); line.setPresentation(.all, requestFocus: false); line.setViewportWidth(1000)
        let keyboard = LineKeyboard(line: line, onCopy: { _ in }, onPreview: { _ in }, onClose: {})
        var pastes = [[UUID]](), tags = [[UUID]](), ocr = [UUID](), commands = 0
        line.onPasteRequested = { pastes.append($0) }; line.onTagRequested = { tags.append($0) }
        line.onImageTextCopyRequested = { ocr.append($0) }; line.onCommandsRequested = { commands += 1 }
        try line.keyboardBindings.set([KeyShortcut(keyCode: 6, modifiers: controlKey, keyLabel: "Z")], for: .select1)
        try line.keyboardBindings.set([KeyShortcut(keyCode: 38, modifiers: cmdKey, keyLabel: "J")], for: .paste)
        try line.keyboardBindings.set([KeyShortcut(keyCode: 7, modifiers: controlKey | optionKey, keyLabel: "X")], for: .copyImageText)
        try line.keyboardBindings.set([KeyShortcut(keyCode: 15, modifiers: cmdKey | shiftKey, keyLabel: "R")], for: .tag)
        try line.keyboardBindings.set([KeyShortcut(keyCode: 40, modifiers: cmdKey | shiftKey, keyLabel: "K")], for: .commandPalette)
        XCTAssertFalse(keyboard.handle(key(18, text: "1")))
        XCTAssertTrue(keyboard.handle(key(6, flags: .control, text: "z")))
        XCTAssertEqual(line.focusedID, line.displayItems[0].id)
        XCTAssertTrue(keyboard.handle(key(7, flags: [.control, .option], text: "x")))
        XCTAssertEqual(ocr, [line.displayItems[0].id])
        line.texts.selectAll(); line.links.selectAll(); line.selectAll()
        let images = line.displayItems.map(\.id)
        XCTAssertTrue(keyboard.handle(key(38, flags: .command, text: "j")))
        XCTAssertTrue(keyboard.handle(key(15, flags: [.command, .shift], text: "r")))
        XCTAssertEqual(pastes, [images]); XCTAssertEqual(tags, [images])
        line.focusShelf(.texts, requestFocus: false)
        XCTAssertTrue(keyboard.handle(key(38, flags: .command, text: "j")))
        XCTAssertEqual(pastes.last, line.texts.displayEntries.map(\.id))
        XCTAssertTrue(keyboard.handle(key(7, flags: [.control, .option], text: "x")))
        XCTAssertEqual(ocr.count, 1, "OCR cannot run against a stale image focus while the text row is active")
        XCTAssertTrue(keyboard.handle(key(40, flags: [.command, .shift], text: "k")))
        XCTAssertEqual(commands, 1)
        XCTAssertFalse(keyboard.handle(key(36, flags: .command)))
        XCTAssertFalse(keyboard.handle(key(40, flags: .command, text: "k")))
        line.beginShelfSearch(.texts)
        XCTAssertFalse(keyboard.handle(key(38, flags: .command, text: "j")))
        XCTAssertFalse(keyboard.handle(key(15, flags: [.command, .shift], text: "r")))
        XCTAssertTrue(keyboard.handle(key(40, flags: [.command, .shift], text: "k")), "The explicit action-bar shortcut remains available while searching")
        XCTAssertEqual(commands, 2); XCTAssertEqual(pastes.count, 2); XCTAssertEqual(tags.count, 1)
    }

    func testGlobalSearchShortcutDefaultDisableAndCustomPersistenceRejectInvalidValues() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let line = f.line()
        let standard = KeyShortcut(keyCode: 1, modifiers: controlKey | optionKey, keyLabel: "S")
        XCTAssertEqual(line.globalSearchShortcut, standard)
        line.saveGlobalSearchShortcut(nil)
        XCTAssertNil(line.globalSearchShortcut); XCTAssertNil(f.line().globalSearchShortcut)
        let invalid = KeyShortcut(keyCode: 1, modifiers: 0, keyLabel: "S")
        line.saveGlobalSearchShortcut(invalid)
        XCTAssertNil(f.line().globalSearchShortcut, "A rejected plain letter cannot re-enable the global hotkey")
        let custom = KeyShortcut(keyCode: 46, modifiers: cmdKey | optionKey, keyLabel: "M")
        line.saveGlobalSearchShortcut(custom)
        XCTAssertEqual(line.globalSearchShortcut, custom); XCTAssertEqual(f.line().globalSearchShortcut, custom)
        for candidate in [invalid, KeyShortcut(keyCode: 130, modifiers: controlKey, keyLabel: "Invalid"), KeyShortcut(keyCode: 1, modifiers: controlKey, keyLabel: "")] {
            line.saveGlobalSearchShortcut(candidate); XCTAssertEqual(f.line().globalSearchShortcut, custom)
        }
        f.defaults.set(Data("invalid shortcut data".utf8), forKey: "globalSearchShortcut")
        XCTAssertNil(line.globalSearchShortcut, "Corrupt custom data must not register a different hotkey silently")
        line.saveGlobalSearchShortcut(nil)
        XCTAssertNil(f.line().globalSearchShortcut)
    }
}
