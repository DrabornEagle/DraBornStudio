import AppKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class CrossShelfPreviewTests: HistoryTestCase {
    private func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [], text: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
            isARepeat: false, keyCode: code)!
    }
    private func wait(_ predicate: () -> Bool) {
        let end = Date().addingTimeInterval(5)
        while !predicate() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(predicate(), "Cross-shelf preview fixture did not settle")
    }
    private func populate(_ store: LibraryStore, fixture f: SyntheticFixture) throws {
        for i in 0..<4 {
            let record = try store.captureImage(f.image())
            try store.update(record.id) { $0.note = "crosspreview image \(i)" }
            f.date += 1
        }
        for i in 0..<3 { _ = try store.captureText("crosspreview text \(i)"); f.date += 1 }
        for i in 0..<2 { _ = try store.captureLink(try XCTUnwrap(URL(string: "https://example.com/crosspreview/\(i)"))); f.date += 1 }
        // Unmatched newest items ensure navigation uses filtered columns.
        _ = try store.captureImage(f.image()); f.date += 1
        _ = try store.captureText("outside the current query"); f.date += 1
        _ = try store.captureLink(try XCTUnwrap(URL(string: "https://example.com/unmatched")))
    }
    private func search(_ line: Line) {
        line.setPresentation(.all, requestFocus: false)
        line.beginShelfSearch(.images); line.updateShelfSearch("crosspreview", for: .images)
        wait { line.displayItems.count == 4 && line.texts.displayEntries.count == 3 && line.links.displayEntries.count == 2 && !line.shelfSearchIsSearching }
        line.finishShelfSearchEditing(.images, selectFirst: false)
    }
    private func assertSelection(_ line: Line, shelf: Shelf, id: UUID, file: StaticString = #filePath, lineNumber: UInt = #line) {
        XCTAssertEqual(line.activeShelf, shelf, file: file, line: lineNumber)
        XCTAssertEqual(line.selectedIDs, shelf == .images ? [id] : [], file: file, line: lineNumber)
        XCTAssertEqual(line.texts.selectedIDs, shelf == .texts ? [id] : [], file: file, line: lineNumber)
        XCTAssertEqual(line.links.selectedIDs, shelf == .links ? [id] : [], file: file, line: lineNumber)
    }

    func testPreviewShelfNavigationPreservesFilteredColumnAndClearsOtherSelections() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(store, fixture: f)
        let line = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false,
            copyImage: { _ in }, copyText: { _ in }, library: store)
        search(line)
        let images = line.displayItems.map(\.id), texts = line.texts.displayEntries.map(\.id), links = line.links.displayEntries.map(\.id)
        line.selectAll(); line.texts.selectAll(); line.links.selectAll()
        let session = ShelfPreviewSession(line: line, shelf: .images, id: images[3])
        XCTAssertFalse(session.moveShelf(-1)); XCTAssertEqual(session.currentID, images[3])
        let imageSelection = line.selectedIDs, textSelection = line.texts.selectedIDs, linkSelection = line.links.selectedIDs
        XCTAssertFalse(session.moveShelf(1, canPresent: { shelf, id in
            XCTAssertEqual(shelf, .texts); XCTAssertEqual(id, texts[2]); return false
        }))
        XCTAssertEqual(session.shelf, .images); XCTAssertEqual(session.currentID, images[3])
        XCTAssertEqual(line.selectedIDs, imageSelection); XCTAssertEqual(line.texts.selectedIDs, textSelection); XCTAssertEqual(line.links.selectedIDs, linkSelection)
        XCTAssertTrue(session.moveShelf(1)); XCTAssertEqual(session.shelf, .texts); XCTAssertEqual(session.currentID, texts[2])
        assertSelection(line, shelf: .texts, id: texts[2])
        XCTAssertTrue(session.move(-1)); XCTAssertEqual(session.currentID, texts[1]); XCTAssertEqual(session.shelf, .texts)
        XCTAssertTrue(session.moveShelf(1)); XCTAssertEqual(session.currentID, links[1])
        assertSelection(line, shelf: .links, id: links[1])
        XCTAssertFalse(session.moveShelf(1)); XCTAssertEqual(session.currentID, links[1])
        XCTAssertTrue(session.moveShelf(-1)); XCTAssertEqual(session.currentID, texts[1])
        XCTAssertTrue(session.moveShelf(-1)); XCTAssertEqual(session.currentID, images[1])
        assertSelection(line, shelf: .images, id: images[1])
        XCTAssertEqual(line.presentation, .all); XCTAssertEqual(line.shelfSearchQuery, "crosspreview")
    }

    func testPreviewShelfNavigationSkipsHiddenEmptyAndRecordingOnlyRows() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        let image = try store.captureImage(f.image())
        let movie = f.inbox.appendingPathComponent("preview-recording.mov")
        try Data([0]).write(to: movie)
        let recording = try store.captureImage(movie)
        _ = try store.captureText("a text"); _ = try store.captureLink(try XCTUnwrap(URL(string: "https://example.com/preview")))
        let line = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false,
            copyImage: { _ in }, copyText: { _ in }, library: store)
        line.setPresentation(.all, requestFocus: false)
        let link = try XCTUnwrap(line.links.displayEntries.first)
        let session = ShelfPreviewSession(line: line, shelf: .links, id: link.id)
        line.texts.setFavoritesOnly(true)
        XCTAssertTrue(session.moveShelf(-1)); XCTAssertEqual(session.shelf, .images)
        XCTAssertEqual(session.currentID, image.id); XCTAssertFalse(session.ids.contains(recording.id))
        XCTAssertTrue(session.moveShelf(1)); XCTAssertEqual(session.shelf, .links)
        line.setPresentation(.textsLinks, requestFocus: false)
        XCTAssertFalse(session.moveShelf(-1)); XCTAssertEqual(session.shelf, .links)
        XCTAssertEqual(line.presentation, .textsLinks, "Preview arrows must not reveal hidden rows")
        line.setPresentation(.all, requestFocus: false)
        try store.removeFromShelf([image.id])
        XCTAssertEqual(line.displayItems.map(\.id), [recording.id])
        XCTAssertFalse(session.moveShelf(-1), "A recording uses Quick Look and is not a cross-shelf preview candidate")
        XCTAssertEqual(session.currentID, link.id); XCTAssertEqual(session.shelf, .links)
        XCTAssertFalse(session.moveShelf(0))
    }

    func testAppPreviewChangesKindsInSameVisiblePanelAndRoutesCurrentCopyAndPin() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(store, fixture: f)
        var imageCopies = [URL](), textCopies = [String]()
        let line = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false,
            copyImage: { imageCopies.append($0) }, copyText: { textCopies.append($0) }, library: store)
        search(line)
        let board = NSPasteboard(name: NSPasteboard.Name("local.clipboardline.cross-shelf.\(UUID())"))
        defer { board.releaseGlobally() }
        let app = AppDelegate(line: line, watchesFiles: false, copyPasteboard: board)
        app.showPreview(line.displayItems[1].id)
        let panel = try XCTUnwrap(app.preview?.window as? ActionPreviewPanel)
        defer { panel.close() }
        let number = panel.windowNumber
        var closeNotifications = 0
        let observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: nil) { _ in closeNotifications += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        func assertPanel(_ window: NSWindow?, shelf: Shelf, file: StaticString = #filePath, lineNumber: UInt = #line) throws {
            let current = try XCTUnwrap(window, file: file, line: lineNumber)
            XCTAssertTrue(current === panel, file: file, line: lineNumber)
            XCTAssertEqual(current.windowNumber, number, file: file, line: lineNumber)
            XCTAssertTrue(current.isVisible, file: file, line: lineNumber)
            XCTAssertEqual(app.previewSession?.shelf, shelf, file: file, line: lineNumber)
        }
        let secondImage = line.displayItems[2]
        XCTAssertTrue(panel.onKey?(key(124)) ?? false)
        XCTAssertEqual(app.previewSession?.currentID, secondImage.id)
        XCTAssertTrue(panel.onKey?(key(8, flags: .command, text: "c")) ?? false); XCTAssertEqual(imageCopies, [secondImage.url])
        XCTAssertTrue(panel.onKey?(key(35, text: "p")) ?? false)
        XCTAssertTrue(try store.item(secondImage.id)?.favorite == true)
        XCTAssertTrue(panel.onKey?(key(125)) ?? false)
        try assertPanel(app.textPreview?.window, shelf: .texts)
        XCTAssertNil(app.preview); XCTAssertNil(app.linkPreview)
        let text = line.texts.displayEntries[2]
        XCTAssertEqual(app.textPreview?.textView.string, text.text)
        XCTAssertTrue(panel.onKey?(key(8, flags: .command, text: "c")) ?? false); XCTAssertEqual(textCopies, [text.text])
        XCTAssertTrue(panel.onKey?(key(35, text: "p")) ?? false)
        XCTAssertTrue(try store.item(text.id)?.favorite == true)
        XCTAssertTrue(panel.onKey?(key(125)) ?? false)
        try assertPanel(app.linkPreview?.window, shelf: .links)
        XCTAssertNil(app.preview); XCTAssertNil(app.textPreview)
        let currentLink = try XCTUnwrap(app.previewSession?.linkRecord)
        XCTAssertTrue(panel.onKey?(key(8, flags: .command, text: "c")) ?? false)
        XCTAssertEqual(textCopies.last, currentLink.originalURL)
        XCTAssertTrue(panel.onKey?(key(35, text: "p")) ?? false)
        XCTAssertTrue(try store.item(currentLink.id)?.favorite == true)
        XCTAssertTrue(panel.onKey?(key(125)) ?? false)
        try assertPanel(app.linkPreview?.window, shelf: .links)
        // Remapping applies to the preview action, not just the shelf router.
        try line.keyboardBindings.set([KeyShortcut(keyCode: 38, modifiers: 0, keyLabel: "J")], for: .up)
        XCTAssertFalse(panel.onKey?(key(126)) ?? false)
        XCTAssertTrue(panel.onKey?(key(38, text: "j")) ?? false)
        try assertPanel(app.textPreview?.window, shelf: .texts)
        XCTAssertTrue(panel.onKey?(key(38, text: "j")) ?? false)
        try assertPanel(app.preview?.window, shelf: .images)
        XCTAssertNil(app.textPreview); XCTAssertNil(app.linkPreview)
        XCTAssertEqual(closeNotifications, 0, "Changing preview kinds must not close and reopen the same panel")
    }

    func testPreviewReturnCopiesDisplayedItemAndClosesWhileCommandCopyAndToolbarStayOpen() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        let image = try store.captureImage(f.image())
        let note = try XCTUnwrap(store.captureText("Synthetic preview copy and close note"))
        let link = try XCTUnwrap(store.captureLink(URL(string: "https://example.com/preview-copy-and-close")!))
        var imageCopies = [URL](), textCopies = [String]()
        let line = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false,
            copyImage: { imageCopies.append($0) }, copyText: { textCopies.append($0) }, library: store)
        line.setPresentation(.all, requestFocus: false)
        let app = AppDelegate(line: line, watchesFiles: false)
        defer { app.previewWindow?.close() }
        for code: UInt16 in [36, 76] {
            for (shelf, id) in [(Shelf.images, image.id), (.texts, note.id), (.links, link.id)] {
                imageCopies.removeAll(); textCopies.removeAll()
                switch shelf {
                case .images: app.showPreview(id)
                case .texts: app.showTextPreview(id)
                case .links: app.showLinkPreview(id)
                }
                let panel = try XCTUnwrap(app.previewWindow), session = try XCTUnwrap(app.previewSession)
                let controls = try XCTUnwrap(app.preview?.controls ?? app.textPreview?.controls ?? app.linkPreview?.controls)
                controls.onCopy()
                XCTAssertTrue(panel.isVisible); XCTAssertTrue(app.previewSession === session)
                XCTAssertTrue(panel.onKey?(key(8, flags: .command, text: "c")) ?? false)
                XCTAssertTrue(panel.isVisible); XCTAssertTrue(app.previewSession === session)
                XCTAssertTrue(panel.onKey?(key(code)) ?? false)
                XCTAssertFalse(panel.isVisible, "Return and keypad Enter close the preview after copying")
                XCTAssertNil(app.previewWindow); XCTAssertNil(app.previewSession)
                XCTAssertNil(app.preview); XCTAssertNil(app.textPreview); XCTAssertNil(app.linkPreview)
                if shelf == .images {
                    XCTAssertEqual(imageCopies, Array(repeating: try XCTUnwrap(image.fileURL), count: 3))
                    XCTAssertTrue(textCopies.isEmpty)
                } else {
                    XCTAssertTrue(imageCopies.isEmpty)
                    XCTAssertEqual(textCopies, Array(repeating: shelf == .texts ? note.text! : link.originalURL!, count: 3))
                }
            }
        }
    }

    func testPreviewReturnKeepsFailedCopiesAndEditableDraftsOpen() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        let image = try store.captureImage(f.image())
        let note = try XCTUnwrap(store.captureText("Synthetic original preview draft"))
        var textCopies = [String]()
        let line = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false,
            copyText: { textCopies.append($0) }, library: store)
        line.setPresentation(.all, requestFocus: false)
        let app = AppDelegate(line: line, watchesFiles: false)
        defer { app.textPreview?.onSave = { _ in true }; app.previewWindow?.close() }
        app.showPreview(image.id)
        let panel = try XCTUnwrap(app.previewWindow), session = try XCTUnwrap(app.previewSession)
        line.onFlushPreview = { false }
        XCTAssertTrue(panel.onKey?(key(36)) ?? false)
        XCTAssertTrue(panel.isVisible); XCTAssertTrue(app.previewSession === session)
        XCTAssertNil(line.copiedID, "A rejected save must not be treated as a successful copy")
        line.onFlushPreview = { true }
        try FileManager.default.removeItem(at: XCTUnwrap(image.fileURL))
        XCTAssertTrue(panel.onKey?(key(76)) ?? false)
        XCTAssertTrue(panel.isVisible); XCTAssertTrue(app.previewSession === session)
        XCTAssertNil(line.copiedID, "An unreadable file keeps the displayed preview open")
        XCTAssertFalse(ShelfPreviewSession(line: line, shelf: .images, id: UUID()).copy())
        XCTAssertFalse(ShelfPreviewSession(line: line, shelf: .texts, id: UUID()).copy())
        XCTAssertFalse(ShelfPreviewSession(line: line, shelf: .links, id: UUID()).copy())

        app.showTextPreview(note.id)
        let text = try XCTUnwrap(app.textPreview), textPanel = try XCTUnwrap(app.previewWindow)
        text.beginEditing(); text.textView.string = "Synthetic draft with a newline\nkept in the editor"
        text.textDidChange(Notification(name: NSText.didChangeNotification, object: text.textView))
        let draft = text.textView.string, save = text.onSave
        for code: UInt16 in [36, 76] {
            XCTAssertFalse(textPanel.onKey?(key(code)) ?? false, "The native editor owns Return while typing")
            XCTAssertTrue(text.isEditing); XCTAssertTrue(textPanel.isVisible)
            XCTAssertEqual(text.textView.string, draft); XCTAssertTrue(textCopies.isEmpty)
        }
        text.onSave = { _ in false }
        XCTAssertTrue(textPanel.onKey?(key(36, flags: .command)) ?? false)
        XCTAssertTrue(text.isEditing); XCTAssertTrue(textPanel.isVisible)
        XCTAssertTrue(textCopies.isEmpty); XCTAssertEqual(try store.item(note.id)?.text, note.text)
        text.onSave = save
        XCTAssertTrue(text.finishEditing())
        XCTAssertTrue(textPanel.onKey?(key(36)) ?? false)
        XCTAssertEqual(textCopies, [draft]); XCTAssertFalse(textPanel.isVisible)
        XCTAssertNil(app.previewSession)
    }

    func testTextDraftStaysInEditorUntilSavedBeforeCrossShelfNavigation() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(store, fixture: f)
        let line = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false,
            copyImage: { _ in }, copyText: { _ in }, library: store)
        line.setPresentation(.all, requestFocus: false)
        let app = AppDelegate(line: line, watchesFiles: false)
        let id = line.texts.entries[0].id
        app.showTextPreview(id)
        let text = try XCTUnwrap(app.textPreview), panel = try XCTUnwrap(text.window as? ActionPreviewPanel)
        defer { panel.close() }
        text.beginEditing(); text.textView.string = "Edited İstanbul 🌍"
        text.textDidChange(Notification(name: NSText.didChangeNotification))
        XCTAssertFalse(panel.onKey?(key(125)) ?? false)
        XCTAssertFalse(panel.onKey?(key(126)) ?? false)
        XCTAssertFalse(panel.onKey?(key(124)) ?? false)
        XCTAssertEqual(app.previewSession?.currentID, id); XCTAssertTrue(text.isEditing)
        let save = text.onSave; text.onSave = { _ in false }
        XCTAssertTrue(panel.onKey?(key(36, flags: .command)) ?? false)
        XCTAssertTrue(text.isEditing); XCTAssertEqual(text.textView.string, "Edited İstanbul 🌍")
        XCTAssertFalse(panel.onKey?(key(125)) ?? false); XCTAssertEqual(app.previewSession?.shelf, .texts)
        text.onSave = save
        XCTAssertTrue(panel.onKey?(key(36, flags: .command)) ?? false)
        XCTAssertFalse(text.isEditing); XCTAssertEqual(try store.item(id)?.text, "Edited İstanbul 🌍")
        XCTAssertTrue(panel.onKey?(key(125)) ?? false)
        XCTAssertEqual(app.previewSession?.shelf, .links); XCTAssertTrue(app.linkPreview?.window === panel)
        XCTAssertTrue(panel.onKey?(key(126)) ?? false)
        XCTAssertEqual(app.previewSession?.shelf, .texts); XCTAssertTrue(app.textPreview?.window === panel)
        XCTAssertEqual(app.textPreview?.textView.string, "Edited İstanbul 🌍")
        XCTAssertTrue(panel.isVisible)
    }

    func testUnreadableDestinationImageKeepsCurrentPreviewAndSelectionVisible() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        let image = try f.image(); _ = try store.captureImage(image)
        let note = try XCTUnwrap(store.captureText("Keep this preview open"))
        let line = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false,
            copyImage: { _ in }, copyText: { _ in }, library: store)
        line.setPresentation(.both, requestFocus: false)
        let app = AppDelegate(line: line, watchesFiles: false)
        app.showTextPreview(note.id)
        let text = try XCTUnwrap(app.textPreview), panel = try XCTUnwrap(text.window as? ActionPreviewPanel)
        defer { panel.close() }
        let surface = panel.contentView, session = app.previewSession, number = panel.windowNumber
        try FileManager.default.removeItem(at: image)
        XCTAssertTrue(panel.onKey?(key(126)) ?? false)
        XCTAssertTrue(app.previewSession === session); XCTAssertEqual(app.previewSession?.shelf, .texts)
        XCTAssertEqual(app.previewSession?.currentID, note.id); XCTAssertTrue(app.textPreview === text)
        XCTAssertNil(app.preview); XCTAssertNil(app.linkPreview)
        XCTAssertTrue(panel.contentView === surface); XCTAssertEqual(panel.windowNumber, number)
        XCTAssertTrue(panel.isVisible); XCTAssertEqual(text.textView.string, note.text)
        assertSelection(line, shelf: .texts, id: note.id)
        XCTAssertEqual(line.presentation, .both)
    }
}
