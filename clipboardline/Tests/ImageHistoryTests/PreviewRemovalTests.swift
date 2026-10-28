import AppKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class PreviewRemovalTests: HistoryTestCase {
    private func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [], text: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
            isARepeat: false, keyCode: code)!
    }
    private func wait(_ predicate: () -> Bool) {
        let end = Date().addingTimeInterval(5)
        while !predicate() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(predicate(), "Preview removal fixture did not settle")
    }
    private func populate(_ store: LibraryStore, fixture f: SyntheticFixture, count: Int = 3) throws {
        for i in 0..<count {
            let image = try store.captureImage(f.image())
            try store.update(image.id) { $0.note = "previewremove image \(i)" }
            _ = try store.captureText("previewremove text \(i)")
            _ = try store.captureLink(try XCTUnwrap(URL(string: "https://example.com/previewremove/\(i)")))
            f.date += 1
        }
    }
    private func line(_ f: SyntheticFixture, store: LibraryStore,
                      copyImage: @escaping (URL) -> Void = { _ in }, copyText: @escaping (String) -> Void = { _ in }) -> Line {
        let value = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false,
            copyImage: copyImage, copyText: copyText, library: store)
        value.setPresentation(.all, requestFocus: false)
        return value
    }
    private func ids(_ line: Line, _ shelf: Shelf) -> [UUID] {
        switch shelf {
        case .images: line.displayItems.filter { !$0.falling && !$0.isRecording }.map(\.id)
        case .texts: line.texts.displayEntries.map(\.id)
        case .links: line.links.displayEntries.map(\.id)
        }
    }
    private func selected(_ line: Line, _ shelf: Shelf) -> Set<UUID> {
        switch shelf { case .images: line.selectedIDs; case .texts: line.texts.selectedIDs; case .links: line.links.selectedIDs }
    }
    private func show(_ app: AppDelegate, shelf: Shelf, id: UUID) {
        switch shelf { case .images: app.showPreview(id); case .texts: app.showTextPreview(id); case .links: app.showLinkPreview(id) }
    }
    private func assertCurrent(_ app: AppDelegate, panel: ActionPreviewPanel, shelf: Shelf, id: UUID,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.previewWindow === panel, file: file, line: line)
        XCTAssertTrue(panel.isVisible, file: file, line: line)
        XCTAssertEqual(app.previewSession?.shelf, shelf, file: file, line: line)
        XCTAssertEqual(app.previewSession?.currentID, id, file: file, line: line)
        XCTAssertTrue(app.previewSession?.hasCurrentItem == true, file: file, line: line)
    }

    func testSessionRemovalActsOnCurrentItemOnlyAndSelectsNextThenPrevious() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(store, fixture: f)
        let line = line(f, store: store)
        for shelf in Shelf.allCases {
            let original = ids(line, shelf)
            line.selectAll(); line.texts.selectAll(); line.links.selectAll()
            let session = ShelfPreviewSession(line: line, shelf: shelf, id: original[1])
            XCTAssertTrue(session.removeCurrent())
            XCTAssertEqual(ids(line, shelf), [original[0], original[2]])
            XCTAssertEqual(session.currentID, original[2]); XCTAssertEqual(selected(line, shelf), [original[2]])
            XCTAssertTrue(session.removeCurrent())
            XCTAssertEqual(session.currentID, original[0]); XCTAssertEqual(selected(line, shelf), [original[0]])
            XCTAssertTrue(session.removeCurrent()); XCTAssertFalse(session.hasCurrentItem)
            XCTAssertEqual(session.position, "0 / 0"); XCTAssertTrue(ids(line, shelf).isEmpty)
            XCTAssertFalse(session.removeCurrent(), "An empty preview must not create another undo entry")
            XCTAssertTrue(session.undoRemoval()); XCTAssertEqual(session.currentID, original[0])
            XCTAssertTrue(session.undoRemoval()); XCTAssertEqual(session.currentID, original[2])
            XCTAssertTrue(session.undoRemoval()); XCTAssertEqual(session.currentID, original[1])
            XCTAssertEqual(ids(line, shelf), original)
        }
    }

    func testPreviewRemoveAndUndoReuseVisiblePanelForEveryKind() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(store, fixture: f)
        let line = line(f, store: store), app = AppDelegate(line: line, watchesFiles: false)
        for shelf in Shelf.allCases {
            let original = ids(line, shelf)
            line.selectAll(); line.texts.selectAll(); line.links.selectAll()
            show(app, shelf: shelf, id: original[1])
            let panel = try XCTUnwrap(app.previewWindow), number = panel.windowNumber
            var closes = 0
            let observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: nil) { _ in closes += 1 }
            defer { NotificationCenter.default.removeObserver(observer) }
            XCTAssertTrue(panel.onKey?(key(1, text: "s")) ?? false)
            assertCurrent(app, panel: panel, shelf: shelf, id: original[2])
            XCTAssertEqual(ids(line, shelf), [original[0], original[2]])
            XCTAssertEqual(selected(line, shelf), [original[2]])
            XCTAssertTrue(panel.onKey?(key(51)) ?? false)
            assertCurrent(app, panel: panel, shelf: shelf, id: original[1])
            XCTAssertEqual(ids(line, shelf), original)
            XCTAssertEqual(panel.windowNumber, number); XCTAssertEqual(closes, 0)
            panel.close()
        }
    }

    func testLastItemRemovalKeepsUndoableEmptyPanelWithoutStaleActions() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(store, fixture: f, count: 1)
        var imageCopies = [URL](), textCopies = [String]()
        let line = line(f, store: store, copyImage: { imageCopies.append($0) }, copyText: { textCopies.append($0) })
        let app = AppDelegate(line: line, watchesFiles: false)
        for shelf in Shelf.allCases {
            let id = try XCTUnwrap(ids(line, shelf).first)
            show(app, shelf: shelf, id: id)
            let panel = try XCTUnwrap(app.previewWindow), number = panel.windowNumber
            XCTAssertTrue(panel.onKey?(key(1, text: "s")) ?? false)
            XCTAssertTrue(app.previewWindow === panel); XCTAssertTrue(panel.isVisible)
            XCTAssertFalse(app.previewSession?.hasCurrentItem ?? true)
            XCTAssertEqual(app.previewSession?.position, "0 / 0")
            XCTAssertNil(app.preview); XCTAssertNil(app.textPreview); XCTAssertNil(app.linkPreview)
            XCTAssertTrue(ids(line, shelf).isEmpty); XCTAssertTrue(selected(line, shelf).isEmpty)
            _ = panel.onKey?(key(36)); _ = panel.onKey?(key(35, text: "p")); _ = panel.onKey?(key(1, text: "s"))
            XCTAssertTrue(imageCopies.isEmpty); XCTAssertTrue(textCopies.isEmpty)
            XCTAssertFalse(try store.item(id)?.favorite ?? true)
            XCTAssertTrue(app.previewWindow === panel); XCTAssertTrue(panel.isVisible)
            XCTAssertTrue(panel.onKey?(key(51)) ?? false)
            assertCurrent(app, panel: panel, shelf: shelf, id: id)
            XCTAssertEqual(ids(line, shelf), [id]); XCTAssertEqual(panel.windowNumber, number)
            panel.close()
        }
    }

    func testFilteredPinnedPreviewRemovalAndUndoStayInsideVisibleResults() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(store, fixture: f, count: 4)
        let line = line(f, store: store)
        for shelf in Shelf.allCases {
            let values = ids(line, shelf)
            try store.toggleFavorite([values[0], values[2]])
            line.focusShelf(shelf, requestFocus: false); line.setActiveFavorites(true)
        }
        _ = try store.captureText("outside filtered preview")
        _ = try store.captureImage(f.image())
        _ = try store.captureLink(try XCTUnwrap(URL(string: "https://example.com/outside")))
        line.beginShelfSearch(.images); line.updateShelfSearch("previewremove", for: .images)
        wait { Shelf.allCases.allSatisfy { self.ids(line, $0).count == 2 } && !line.shelfSearchIsSearching }
        line.finishShelfSearchEditing(.images, selectFirst: false)
        let app = AppDelegate(line: line, watchesFiles: false)
        for shelf in Shelf.allCases {
            let original = ids(line, shelf)
            show(app, shelf: shelf, id: original[0])
            let panel = try XCTUnwrap(app.previewWindow)
            XCTAssertTrue(panel.onKey?(key(1, text: "s")) ?? false)
            wait { self.ids(line, shelf) == [original[1]] && !line.shelfSearchIsSearching }
            assertCurrent(app, panel: panel, shelf: shelf, id: original[1])
            XCTAssertTrue(try store.item(original[0])?.favorite == true)
            XCTAssertTrue(panel.onKey?(key(51)) ?? false)
            wait { self.ids(line, shelf) == original && !line.shelfSearchIsSearching }
            assertCurrent(app, panel: panel, shelf: shelf, id: original[0])
            XCTAssertEqual(line.shelfSearchQuery, "previewremove"); XCTAssertEqual(line.presentation, .all)
            XCTAssertEqual(try store.shelfItems(shelf.libraryKind).count, 5)
            panel.close()
        }
    }

    func testFailedRemovalAndUndoPreserveCurrentRendererAndCanRetry() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(store, fixture: f)
        let line = line(f, store: store), app = AppDelegate(line: line, watchesFiles: false)
        let db = try LibraryDatabase(url: store.databaseURL)
        for shelf in Shelf.allCases {
            let original = ids(line, shelf)
            show(app, shelf: shelf, id: original[1])
            let panel = try XCTUnwrap(app.previewWindow), session = try XCTUnwrap(app.previewSession), surface = panel.contentView
            try db.execute("CREATE TRIGGER fail_preview_remove BEFORE UPDATE ON items WHEN NEW.shelf=0 BEGIN SELECT RAISE(ABORT,'fixture remove failure'); END")
            XCTAssertTrue(panel.onKey?(key(1, text: "s")) ?? false)
            assertCurrent(app, panel: panel, shelf: shelf, id: original[1])
            XCTAssertTrue(app.previewSession === session); XCTAssertTrue(panel.contentView === surface)
            XCTAssertEqual(ids(line, shelf), original); XCTAssertTrue(line.notice != nil)
            try db.execute("DROP TRIGGER fail_preview_remove")
            XCTAssertTrue(panel.onKey?(key(1, text: "s")) ?? false)
            assertCurrent(app, panel: panel, shelf: shelf, id: original[2])
            let nextSurface = panel.contentView
            try db.execute("CREATE TRIGGER fail_preview_undo BEFORE UPDATE ON items WHEN NEW.shelf=1 BEGIN SELECT RAISE(ABORT,'fixture undo failure'); END")
            XCTAssertTrue(panel.onKey?(key(51)) ?? false)
            assertCurrent(app, panel: panel, shelf: shelf, id: original[2])
            XCTAssertTrue(app.previewSession === session); XCTAssertTrue(panel.contentView === nextSurface)
            XCTAssertEqual(ids(line, shelf), [original[0], original[2]])
            try db.execute("DROP TRIGGER fail_preview_undo")
            XCTAssertTrue(panel.onKey?(key(51)) ?? false)
            assertCurrent(app, panel: panel, shelf: shelf, id: original[1])
            XCTAssertEqual(ids(line, shelf), original)
            panel.close()
        }
    }

    func testTextEditingRetainsNativeRemoveKeysAndRestoresSavedDraft() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(store, fixture: f)
        let line = line(f, store: store), app = AppDelegate(line: line, watchesFiles: false)
        let original = ids(line, .texts), id = original[1]
        app.showTextPreview(id)
        let text = try XCTUnwrap(app.textPreview), panel = try XCTUnwrap(app.previewWindow)
        defer { panel.close() }
        text.beginEditing(); text.textView.string = "Saved draft İstanbul 🌍 with an s"
        text.textDidChange(Notification(name: NSText.didChangeNotification))
        XCTAssertFalse(panel.onKey?(key(1, text: "s")) ?? false)
        XCTAssertFalse(panel.onKey?(key(51)) ?? false)
        XCTAssertTrue(text.isEditing); XCTAssertEqual(ids(line, .texts), original)
        XCTAssertEqual(app.previewSession?.currentID, id)
        XCTAssertTrue(panel.onKey?(key(36, flags: .command)) ?? false)
        XCTAssertFalse(text.isEditing)
        XCTAssertTrue(panel.onKey?(key(1, text: "s")) ?? false)
        assertCurrent(app, panel: panel, shelf: .texts, id: original[2])
        XCTAssertEqual(try store.item(id)?.text, "Saved draft İstanbul 🌍 with an s")
        XCTAssertTrue(panel.onKey?(key(51)) ?? false)
        assertCurrent(app, panel: panel, shelf: .texts, id: id)
        XCTAssertEqual(app.textPreview?.textView.string, "Saved draft İstanbul 🌍 with an s")
    }

    func testUndoAfterCrossShelfNavigationRestoresMostRecentRemovalKindInSamePanel() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(store, fixture: f)
        let line = line(f, store: store), app = AppDelegate(line: line, watchesFiles: false)
        let images = ids(line, .images), texts = ids(line, .texts), links = ids(line, .links)
        app.showPreview(images[0])
        let panel = try XCTUnwrap(app.previewWindow)
        defer { panel.close() }
        XCTAssertTrue(panel.onKey?(key(1, text: "s")) ?? false)
        assertCurrent(app, panel: panel, shelf: .images, id: images[1])
        XCTAssertTrue(panel.onKey?(key(125)) ?? false)
        assertCurrent(app, panel: panel, shelf: .texts, id: texts[0])
        XCTAssertTrue(panel.onKey?(key(1, text: "s")) ?? false)
        assertCurrent(app, panel: panel, shelf: .texts, id: texts[1])
        XCTAssertTrue(panel.onKey?(key(125)) ?? false)
        assertCurrent(app, panel: panel, shelf: .links, id: links[0])
        XCTAssertTrue(panel.onKey?(key(51)) ?? false)
        assertCurrent(app, panel: panel, shelf: .texts, id: texts[0])
        XCTAssertTrue(panel.onKey?(key(51)) ?? false)
        assertCurrent(app, panel: panel, shelf: .images, id: images[0])
        XCTAssertEqual(ids(line, .images), images); XCTAssertEqual(ids(line, .texts), texts)
        XCTAssertEqual(ids(line, .links), links)
    }

    func testUnreadableImageAfterRemovalOrUndoKeepsUndoablePanelWithoutStaleActions() throws {
        _ = NSApplication.shared
        for missingOnUndo in [false, true] {
            let f = try SyntheticFixture(); defer { f.cleanup() }
            let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
            try populate(store, fixture: f, count: missingOnUndo ? 1 : 2)
            var copies = [URL]()
            let line = line(f, store: store, copyImage: { copies.append($0) })
            let app = AppDelegate(line: line, watchesFiles: false), original = ids(line, .images)
            let firstURL = try XCTUnwrap(line.items.first { $0.id == original[0] }?.url)
            app.showPreview(original[0])
            let panel = try XCTUnwrap(app.previewWindow), number = panel.windowNumber
            defer { panel.close() }
            var closes = 0
            let observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: nil) { _ in closes += 1 }
            defer { NotificationCenter.default.removeObserver(observer) }
            if !missingOnUndo {
                let nextURL = try XCTUnwrap(line.items.first { $0.id == original[1] }?.url)
                try FileManager.default.removeItem(at: nextURL)
            }
            XCTAssertTrue(panel.onKey?(key(1, text: "s")) ?? false)
            if missingOnUndo {
                XCTAssertFalse(app.previewSession?.hasCurrentItem ?? true)
                try FileManager.default.removeItem(at: firstURL)
                XCTAssertTrue(panel.onKey?(key(51)) ?? false)
            }
            let unavailable = missingOnUndo ? original[0] : original[1]
            assertCurrent(app, panel: panel, shelf: .images, id: unavailable)
            XCTAssertNil(app.preview); XCTAssertNil(app.textPreview); XCTAssertNil(app.linkPreview)
            XCTAssertTrue(try store.item(unavailable)?.onShelf == true)
            XCTAssertTrue(panel.onKey?(key(36)) ?? false)
            XCTAssertTrue(panel.onKey?(key(35, text: "p")) ?? false)
            XCTAssertTrue(copies.isEmpty); XCTAssertFalse(try store.item(unavailable)?.favorite ?? true)
            XCTAssertTrue(app.previewWindow === panel); XCTAssertTrue(panel.isVisible)
            XCTAssertEqual(panel.windowNumber, number); XCTAssertEqual(closes, 0)
            if !missingOnUndo {
                XCTAssertTrue(panel.onKey?(key(51)) ?? false)
                assertCurrent(app, panel: panel, shelf: .images, id: original[0])
                XCTAssertTrue(app.preview?.window === panel)
                XCTAssertEqual(ids(line, .images), original)
                XCTAssertEqual(closes, 0)
            }
        }
    }
}
