import AppKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class ShelfSearchInteractionTests: HistoryTestCase {
    private func wait(_ predicate: () -> Bool) {
        let end = Date().addingTimeInterval(5)
        while !predicate() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(predicate(), "Shelf search interaction did not settle")
    }
    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = [], _ text: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
    }
    func testSharedSearchFiltersAllVisibleShelvesAndNavigationCopyPinAndCloseUseFilteredItems() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        var copied = "", closed = 0, libraryOpened = 0
        let line = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false,
            copyText: { copied = $0 }, library: store)
        let first = try XCTUnwrap(store.captureText("alpha one")), second = try XCTUnwrap(store.captureText("alpha two"))
        let unrelated = try XCTUnwrap(store.captureText("beta unchanged"))
        let link = try store.captureLink(try XCTUnwrap(URL(string: "https://example.com/alpha")))
        _ = try store.captureLink(try XCTUnwrap(URL(string: "https://example.com/beta")))
        let image = try store.captureImage(f.image())
        let database = try LibraryDatabase(url: store.databaseURL, verify: false)
        try database.execute("INSERT INTO image_analysis(item,path,fingerprint,version,content,ocr,vectors) VALUES(?,?,?,?,?,?,?)", [
            .text(image.id.uuidString), .text(try XCTUnwrap(image.path)), .text("synthetic"),
            .text("vision-ocr-v1"), .text("alpha indexed image"), .text("Alpha indexed image"), .blob(Data())
        ])
        line.setPresentation(.all, requestFocus: false); line.revealed = true; line.focusShelf(.texts, requestFocus: false)
        line.onLibraryRequested = { libraryOpened += 1 }
        let keyboard = LineKeyboard(line: line, onCopy: { _ in }, onPreview: { _ in }, onClose: { closed += 1 },
            onTextCopy: { _ in line.texts.copySelection() })
        line.texts.select(unrelated.id, width: 600)
        XCTAssertTrue(keyboard.handle(key(1, .shift, "s")))
        XCTAssertEqual(line.searchEditingShelf, .texts); XCTAssertEqual(libraryOpened, 0)
        line.updateShelfSearch("alpha", for: .texts)
        XCTAssertTrue(line.texts.selectedIDs.isEmpty)
        XCTAssertFalse(keyboard.handle(key(1, [], "s")), "Typing S must not remove an item")
        XCTAssertFalse(keyboard.handle(key(35, [], "p")), "Typing P must not pin an item")
        wait { line.texts.displayEntries.count == 2 && line.links.displayEntries.count == 1 && line.displayItems.count == 1 && Shelf.allCases.allSatisfy { line.shelfSearch?.isSearching(for: $0.libraryKind) == false } }
        XCTAssertEqual(Set(line.texts.displayEntries.map(\.id)), Set([first.id, second.id]))
        XCTAssertEqual(line.links.displayEntries.map(\.id), [link.id])
        XCTAssertEqual(line.displayItems.map(\.id), [image.id], "One phrase also searches cached image OCR")
        XCTAssertEqual(line.shelfSearchQuery, "alpha")
        XCTAssertEqual(line.shelfSearchResultCount, 4)
        XCTAssertTrue(Shelf.allCases.allSatisfy { line.shelfSearch?.query(for: $0.libraryKind) == "alpha" })
        line.finishShelfSearchEditing(.texts)
        XCTAssertTrue(line.texts.focusedID != nil)
        XCTAssertTrue(keyboard.handle(key(124)))
        XCTAssertTrue(keyboard.handle(key(36)))
        XCTAssertTrue(copied.hasPrefix("alpha")); XCTAssertFalse(copied.contains("beta"))
        XCTAssertTrue(keyboard.handle(key(35, [], "p")))
        XCTAssertEqual(try store.item(unrelated.id)?.favorite, false)
        XCTAssertEqual(try store.shelfItems(.text).filter(\.favorite).count, 1)
        XCTAssertTrue(keyboard.handle(key(53))); XCTAssertEqual(closed, 0)
        wait { line.texts.displayEntries.count == 3 && line.links.displayEntries.count == 2 }
        XCTAssertFalse(line.isShelfSearchActive)
        XCTAssertEqual(line.shelfSearchQuery, "")
        XCTAssertTrue(Shelf.allCases.allSatisfy { line.shelfSearch?.isActive(for: $0.libraryKind) == false }, "Escape clears the single shared search in every row")
        XCTAssertNil(line.texts.searchMatchingIDs); XCTAssertNil(line.links.searchMatchingIDs)
        XCTAssertTrue(keyboard.handle(key(53))); XCTAssertEqual(closed, 1)
    }
    func testSharedQueryFollowsVisibleTogglesPinsAndClosingClearsPendingFilters() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        let line = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false, library: store)
        let a = try XCTUnwrap(store.captureText("matching note")), b = try XCTUnwrap(store.captureText("matching other"))
        let link = try store.captureLink(try XCTUnwrap(URL(string: "https://example.com/matching")))
        _ = try store.captureLink(try XCTUnwrap(URL(string: "https://example.com/unrelated")))
        let image = try store.captureImage(f.image())
        try store.update(image.id) { $0.note = "matching image" }
        try store.toggleFavorite([a.id])
        line.setPresentation(.all, requestFocus: false); line.revealed = true
        line.beginShelfSearch(.texts); line.updateShelfSearch("matching", for: .texts)
        wait { line.texts.displayEntries.count == 2 && line.links.displayEntries.count == 1 && line.displayItems.count == 1 && Shelf.allCases.allSatisfy { line.shelfSearch?.isSearching(for: $0.libraryKind) == false } }
        XCTAssertEqual(line.shelfSearchResultCount, 4)
        line.finishShelfSearchEditing(.texts); line.texts.selectAll()
        line.setActiveFavorites(true)
        wait { line.texts.displayEntries.map(\.id) == [a.id] && line.shelfSearch?.isSearching(for: .text) == false }
        XCTAssertFalse(line.texts.selectedIDs.contains(b.id))
        XCTAssertEqual(line.shelfSearchResultCount, 3, "Combined count respects each row's pinned filter")
        // Preview and context-menu filters also use the history's setter.
        line.texts.setFavoritesOnly(false)
        wait { line.texts.displayEntries.count == 2 && line.shelfSearch?.isSearching(for: .text) == false }
        line.texts.setFavoritesOnly(true)
        wait { line.texts.displayEntries.map(\.id) == [a.id] && line.shelfSearch?.isSearching(for: .text) == false }
        line.beginShelfSearch(.links)
        XCTAssertEqual(line.shelfSearchQuery, "matching", "Moving the native editor preserves the same phrase")
        XCTAssertEqual(line.shelfSearch?.query(for: .text), "matching")
        line.setPresentation(.both, requestFocus: false)
        XCTAssertFalse(line.shelfSearch?.isActive(for: .link) ?? true, "Hidden rows cannot keep filtering")
        XCTAssertEqual(line.shelfSearchResultCount, 2, "Closed link rows are excluded from the shared result count")
        XCTAssertTrue(line.isShelfSearchActive)
        XCTAssertEqual(line.shelfSearchQuery, "matching")
        let hiddenCapture = try store.captureLink(try XCTUnwrap(URL(string: "https://example.com/matching/new")))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertFalse(line.shelfSearch?.isActive(for: .link) ?? true, "Capturing into a closed row must not reopen its search")
        XCTAssertEqual(line.shelfSearchResultCount, 2)
        line.setPresentation(.all, requestFocus: false)
        wait { Set(line.links.displayEntries.map(\.id)) == Set([link.id, hiddenCapture.id]) && line.shelfSearch?.isSearching(for: .link) == false }
        XCTAssertEqual(line.shelfSearch?.query(for: .link), "matching", "Reopening a row applies the current phrase")
        XCTAssertEqual(line.shelfSearchResultCount, 4)
        // Hide a row while debounce/read work is pending. Its late callback
        // must not reactivate it, even though clipboard capture stays enabled.
        line.updateShelfSearch("example.com", for: .links)
        line.setPresentation(.both, requestFocus: false)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertFalse(line.shelfSearch?.isActive(for: .link) ?? true)
        XCTAssertNil(line.links.searchMatchingIDs)
        XCTAssertEqual(line.shelfSearchResultCount, 0)
        XCTAssertEqual(line.shelfSearch?.query(for: .text), "example.com", "The caller's row is only a focus anchor, not a query scope")
        line.beginShelfSearch(.texts)
        line.setPresentation(.all, requestFocus: false)
        line.finishShelfSearchEditing(.texts)
        wait { line.links.displayEntries.count == 3 && line.shelfSearch?.isSearching(for: .link) == false && line.activeShelf == .links && line.links.focusedID != nil }
        XCTAssertEqual(line.shelfSearchResultCount, 3)
        XCTAssertEqual(line.activeShelf, .links, "Enter waits for newly visible results and focuses a nonempty row when its anchor has no matches")
        line.updateShelfSearch("not going to survive close", for: .texts); line.revealed = false
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        XCTAssertNil(line.searchEditingShelf); XCTAssertTrue(line.shelfSearch?.states.isEmpty ?? false)
        XCTAssertFalse(line.isShelfSearchActive); XCTAssertEqual(line.shelfSearchQuery, "")
        XCTAssertNil(line.texts.searchMatchingIDs); XCTAssertNil(line.links.searchMatchingIDs)
        line.revealed = true
        XCTAssertEqual(line.activeShelf, .images); XCTAssertEqual(line.selectedIDs, [image.id])
        XCTAssertTrue(line.texts.selectedIDs.isEmpty); XCTAssertTrue(line.links.selectedIDs.isEmpty)
        XCTAssertEqual(line.texts.displayEntries.map(\.id), [a.id], "Pinned filtering survives closing search")
    }
    func testNativeSearchEditorKeepsTypingKeysAndReturnsFocusForBrowsing() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        _ = try store.captureText("sample text")
        let line = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false, library: store)
        line.setPresentation(.texts, requestFocus: false)
        line.revealed = true; line.beginShelfSearch(.texts)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 120))
        let panel = LinePanel(content: content); panel.keyboardFocusAllowed = true
        let field = ShelfSearchTextField(line: line, shelf: .texts)
        field.frame = NSRect(x: 10, y: 40, width: 300, height: 24); content.addSubview(field)
        defer { panel.makeFirstResponder(nil); panel.contentView = nil }
        XCTAssertTrue(panel.makeFirstResponder(field)); field.selectText(nil)
        var routed = 0; panel.onKey = { _ in routed += 1; return true }
        XCTAssertFalse(panel.routeKey(key(1, [], "s"), isFocused: true))
        XCTAssertFalse(panel.routeKey(key(51), isFocused: true)); XCTAssertEqual(routed, 0)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        field.stringValue = "sample"; field.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        XCTAssertFalse(field.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
        XCTAssertFalse(field.control(field, textView: editor, doCommandBy: #selector(NSResponder.deleteBackward(_:))))
        XCTAssertTrue(field.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertNil(line.searchEditingShelf)
        XCTAssertTrue(line.shelfSearch?.isActive(for: .text) ?? false)
        XCTAssertTrue(panel.routeKey(key(124), isFocused: true)); XCTAssertEqual(routed, 1)
        line.beginShelfSearch(.texts)
        XCTAssertTrue(panel.makeFirstResponder(field)); field.selectText(nil)
        let oldEditor = try XCTUnwrap(field.currentEditor())
        line.focusShelf(.texts)
        field.synchronize()
        XCTAssertNil(line.searchEditingShelf, "Clicking a card in the same row must return to browsing")
        XCTAssertFalse(panel.firstResponder === oldEditor)
    }
    func testImageResultClickLeavesNativeEditorAndKeepsSearchFilter() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        let line = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false, copyImage: { _ in }, library: store)
        _ = line.hang(try f.image(), quietly: true)
        let image = try XCTUnwrap(line.items.first)
        line.revealed = true; line.beginShelfSearch(.images)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 120)), field = ShelfSearchTextField(line: line, shelf: .images)
        let panel = LinePanel(content: content); panel.keyboardFocusAllowed = true
        field.frame = NSRect(x: 10, y: 40, width: 300, height: 24); content.addSubview(field)
        defer { panel.makeFirstResponder(nil); panel.contentView = nil }
        XCTAssertTrue(panel.makeFirstResponder(field)); field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor())
        line.onFocusRequested = { field.synchronize() }
        let grab = GrabView(); GrabArea(item: image, line: line).configure(grab)
        grab.onClick([])
        XCTAssertNil(line.searchEditingShelf); XCTAssertFalse(panel.firstResponder === editor)
        XCTAssertEqual(line.focusedID, image.id)
        XCTAssertTrue(line.shelfSearch?.isActive(for: .image) ?? false)
    }
}
