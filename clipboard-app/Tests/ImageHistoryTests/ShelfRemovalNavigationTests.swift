import AppKit
import Carbon
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class ShelfRemovalNavigationTests: HistoryTestCase {
    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = [], _ text: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
            isARepeat: false, keyCode: code)!
    }
    private func wait(_ predicate: () -> Bool) {
        let end = Date().addingTimeInterval(5)
        while !predicate() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(predicate(), "Shelf removal fixture did not settle")
    }
    private func populate(_ store: LibraryStore, fixture f: SyntheticFixture) throws {
        for i in 0..<6 {
            let image = try store.captureImage(f.image())
            let text = try XCTUnwrap(store.captureText(i < 4 ? "removalmatch text \(i)" : "outside text \(i)"))
            let link = try store.captureLink(try XCTUnwrap(URL(string: "https://example.com/\(i < 4 ? "removalmatch" : "outside")/\(i)")))
            try store.update(image.id) { $0.note = i < 4 ? "removalmatch image \(i)" : "outside image \(i)" }
            if i == 1 || i == 3 || i == 5 { try store.toggleFavorite([image.id, text.id, link.id]) }
            f.date += 1
        }
    }
    private func line(_ f: SyntheticFixture, store: LibraryStore) -> Line {
        let value = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false,
            copyImage: { _ in }, copyText: { _ in }, library: store)
        value.setPresentation(.all, requestFocus: false)
        return value
    }
    private func keyboard(_ line: Line) -> LineKeyboard {
        LineKeyboard(line: line, onCopy: { _ in }, onPreview: { _ in }, onClose: {})
    }
    private func ids(_ line: Line, _ shelf: Shelf) -> [UUID] {
        switch shelf {
        case .images: line.displayItems.filter { !$0.falling }.map(\.id)
        case .texts: line.texts.displayEntries.map(\.id)
        case .links: line.links.displayEntries.map(\.id)
        }
    }
    private func focused(_ line: Line, _ shelf: Shelf) -> UUID? {
        switch shelf { case .images: line.focusedID; case .texts: line.texts.focusedID; case .links: line.links.focusedID }
    }
    private func selected(_ line: Line, _ shelf: Shelf) -> Set<UUID> {
        switch shelf { case .images: line.selectedIDs; case .texts: line.texts.selectedIDs; case .links: line.links.selectedIDs }
    }
    private func select(_ id: UUID, on shelf: Shelf, in line: Line, toggle: Bool = false) {
        line.focusShelf(shelf, requestFocus: false)
        switch shelf {
        case .images: line.select(id, toggle: toggle)
        case .texts: line.texts.select(id, toggle: toggle, width: line.viewportWidth)
        case .links: line.links.select(id, toggle: toggle, width: line.viewportWidth)
        }
    }
    private func search(_ line: Line) {
        line.beginShelfSearch(.images); line.updateShelfSearch("removalmatch", for: .images)
        wait { Shelf.allCases.allSatisfy { self.ids(line, $0).count == 4 } && !line.shelfSearchIsSearching }
        line.finishShelfSearchEditing(.images, selectFirst: false)
    }

    func testRepeatedShelfRemovalSelectsNextThenPreviousAndFinallyClearsEveryKind() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(store, fixture: f)
        let line = line(f, store: store), keyboard = keyboard(line)
        for shelf in Shelf.allCases {
            let original = ids(line, shelf)
            select(original[1], on: shelf, in: line)
            for next in original.dropFirst(2) {
                XCTAssertTrue(keyboard.handle(key(1, [], "s")))
                XCTAssertEqual(focused(line, shelf), next)
                XCTAssertEqual(selected(line, shelf), [next])
                XCTAssertEqual(line.activeShelf, shelf)
            }
            // Removing the oldest item keeps the nearest survivor to its left.
            XCTAssertTrue(keyboard.handle(key(1, [], "s")))
            XCTAssertEqual(focused(line, shelf), original[0])
            XCTAssertEqual(selected(line, shelf), [original[0]])
            XCTAssertTrue(keyboard.handle(key(1, [], "s")))
            XCTAssertTrue(ids(line, shelf).isEmpty)
            XCTAssertNil(focused(line, shelf)); XCTAssertTrue(selected(line, shelf).isEmpty)
            XCTAssertTrue(keyboard.handle(key(1, [], "s")), "Repeated removal of an empty row is harmless")
            XCTAssertEqual(line.activeShelf, shelf); XCTAssertEqual(line.presentation, .all)
        }
    }

    func testBatchRemovalAnchorsAtFocusedVisibleItemAndFallsBackToEarliestSelection() throws {
        // The focused item determines forward movement. A toggled-off focus
        // falls back to the first selected item rather than jumping arbitrarily.
        let selections = [[1, 2], [4, 1], [1, 3, 3], [4, 5]]
        let expected = [3, 2, 2, 3]
        for shelf in Shelf.allCases {
            for (index, sequence) in selections.enumerated() {
                let f = try SyntheticFixture(); defer { f.cleanup() }
                let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
                try populate(store, fixture: f)
                let line = line(f, store: store), keyboard = keyboard(line), original = ids(line, shelf)
                for (step, column) in sequence.enumerated() { select(original[column], on: shelf, in: line, toggle: step > 0) }
                let removed = selected(line, shelf)
                XCTAssertTrue(keyboard.handle(key(1, [], "s")))
                XCTAssertEqual(ids(line, shelf), original.filter { !removed.contains($0) })
                XCTAssertEqual(focused(line, shelf), original[expected[index]])
                XCTAssertEqual(selected(line, shelf), [original[expected[index]]])
                XCTAssertEqual(line.activeShelf, shelf)
            }
        }
    }

    func testSearchAndPinnedRemovalAndBoundaryNavigationUseOnlyDisplayedResults() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(store, fixture: f)
        let line = line(f, store: store), keyboard = keyboard(line)
        search(line)
        for shelf in Shelf.allCases {
            line.focusShelf(shelf, requestFocus: false); line.setActiveFavorites(true)
            wait { self.ids(line, shelf).count == 2 && !line.shelfSearchIsSearching }
            let visible = ids(line, shelf)
            XCTAssertTrue(keyboard.handle(key(124, .command)))
            XCTAssertEqual(focused(line, shelf), visible.last)
            XCTAssertTrue(keyboard.handle(key(123, .command)))
            XCTAssertEqual(focused(line, shelf), visible.first)
            XCTAssertTrue(keyboard.handle(key(1, [], "s")))
            wait { self.ids(line, shelf) == [visible[1]] && !line.shelfSearchIsSearching }
            XCTAssertEqual(focused(line, shelf), visible[1]); XCTAssertEqual(selected(line, shelf), [visible[1]])
            XCTAssertTrue(keyboard.handle(key(1, [], "s")))
            wait { self.ids(line, shelf).isEmpty && !line.shelfSearchIsSearching }
            XCTAssertNil(focused(line, shelf)); XCTAssertTrue(selected(line, shelf).isEmpty)
            XCTAssertTrue(keyboard.handle(key(123, .command))); XCTAssertTrue(keyboard.handle(key(124, .command)))
            XCTAssertNil(focused(line, shelf), "An empty filtered row must not choose a hidden or unpinned record")
            XCTAssertEqual(try store.shelfItems(shelf.libraryKind).count, 4, "Only the two displayed pinned matches were removed")
        }
        XCTAssertEqual(line.shelfSearchQuery, "removalmatch"); XCTAssertEqual(line.presentation, .all)
    }

    func testFailedShelfRemovalPreservesSelectionAndRetrySelectsNeighbor() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(store, fixture: f)
        let line = line(f, store: store), keyboard = keyboard(line)
        let db = try LibraryDatabase(url: store.databaseURL)
        for shelf in Shelf.allCases {
            let original = ids(line, shelf)
            select(original[1], on: shelf, in: line); select(original[2], on: shelf, in: line, toggle: true)
            try db.execute("CREATE TRIGGER fail_test_removal BEFORE UPDATE ON items WHEN NEW.shelf=0 BEGIN SELECT RAISE(ABORT,'fixture failure'); END")
            XCTAssertTrue(keyboard.handle(key(1, [], "s")))
            XCTAssertEqual(ids(line, shelf), original)
            XCTAssertEqual(selected(line, shelf), Set([original[1], original[2]])); XCTAssertEqual(focused(line, shelf), original[2])
            XCTAssertTrue(line.notice != nil)
            try db.execute("DROP TRIGGER fail_test_removal")
            XCTAssertTrue(keyboard.handle(key(1, [], "s")))
            XCTAssertEqual(selected(line, shelf), [original[3]]); XCTAssertEqual(focused(line, shelf), original[3])
        }
    }

    func testCommandArrowBoundariesRespectActiveShelfRemappingAndNativeSearchEditing() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(store, fixture: f)
        let line = line(f, store: store), keyboard = keyboard(line)
        line.setViewportWidth(320)
        for shelf in Shelf.allCases {
            let values = ids(line, shelf)
            select(values[2], on: shelf, in: line)
            XCTAssertTrue(keyboard.handle(key(124, .command))); XCTAssertEqual(focused(line, shelf), values.last)
            XCTAssertEqual(selected(line, shelf), [values.last!]); XCTAssertEqual(line.activeShelf, shelf)
            XCTAssertTrue(keyboard.handle(key(123, .command))); XCTAssertEqual(focused(line, shelf), values.first)
            XCTAssertEqual(selected(line, shelf), [values.first!]); XCTAssertEqual(line.activeShelf, shelf)
        }
        try line.keyboardBindings.set([KeyShortcut(keyCode: 115, modifiers: controlKey, keyLabel: "Home")], for: .first)
        try line.keyboardBindings.set([KeyShortcut(keyCode: 119, modifiers: controlKey, keyLabel: "End")], for: .last)
        XCTAssertFalse(keyboard.handle(key(124, .command))); XCTAssertFalse(keyboard.handle(key(123, .command)))
        XCTAssertTrue(keyboard.handle(key(119, .control))); XCTAssertEqual(line.links.focusedID, line.links.displayEntries.last?.id)
        XCTAssertTrue(keyboard.handle(key(115, .control))); XCTAssertEqual(line.links.focusedID, line.links.displayEntries.first?.id)
        line.beginShelfSearch(.links)
        let focused = line.links.focusedID
        XCTAssertFalse(keyboard.handle(key(119, .control))); XCTAssertFalse(keyboard.handle(key(115, .control)))
        XCTAssertEqual(line.links.focusedID, focused, "Editing the search query must retain native caret shortcuts")
        XCTAssertEqual(line.presentation, .all)
    }

    func testPreviewCommandBoundariesKeepPanelAndRespectTextEditing() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(store, fixture: f)
        let line = line(f, store: store)
        search(line)
        let app = AppDelegate(line: line, watchesFiles: false)
        app.showPreview(line.displayItems[1].id)
        let panel = try XCTUnwrap(app.preview?.window as? ActionPreviewPanel)
        defer { panel.close() }
        for shelf in Shelf.allCases {
            if shelf != .images { XCTAssertTrue(panel.onKey?(key(125)) ?? false) }
            let values = ids(line, shelf)
            XCTAssertEqual(app.previewSession?.shelf, shelf)
            XCTAssertTrue(panel.onKey?(key(124, .command)) ?? false)
            XCTAssertEqual(app.previewSession?.currentID, values.last)
            XCTAssertTrue(panel.onKey?(key(123, .command)) ?? false)
            XCTAssertEqual(app.previewSession?.currentID, values.first)
            XCTAssertEqual(focused(line, shelf), values.first)
            let currentWindow: NSWindow? = shelf == .images ? app.preview?.window : shelf == .texts ? app.textPreview?.window : app.linkPreview?.window
            XCTAssertTrue(currentWindow === panel); XCTAssertTrue(panel.isVisible)
            if shelf == .texts {
                let text = try XCTUnwrap(app.textPreview)
                text.beginEditing(); text.textView.string = "removalmatch Edited boundary note İstanbul 🌍"
                text.textDidChange(Notification(name: NSText.didChangeNotification))
                XCTAssertFalse(panel.onKey?(key(124, .command)) ?? false)
                XCTAssertFalse(panel.onKey?(key(123, .command)) ?? false)
                XCTAssertEqual(app.previewSession?.currentID, values.first)
                XCTAssertTrue(text.isEditing)
                XCTAssertTrue(panel.onKey?(key(36, .command)) ?? false)
                XCTAssertFalse(text.isEditing)
                XCTAssertTrue(panel.onKey?(key(124, .command)) ?? false)
                XCTAssertEqual(app.previewSession?.currentID, values.last)
                XCTAssertEqual(try store.item(values[0])?.text, "removalmatch Edited boundary note İstanbul 🌍")
            }
        }
        try line.keyboardBindings.set([KeyShortcut(keyCode: 115, modifiers: controlKey, keyLabel: "Home")], for: .first)
        XCTAssertFalse(panel.onKey?(key(123, .command)) ?? false)
        XCTAssertTrue(panel.onKey?(key(115, .control)) ?? false)
        XCTAssertEqual(app.previewSession?.currentID, line.links.displayEntries.first?.id)
        XCTAssertTrue(app.linkPreview?.window === panel)
    }
}
