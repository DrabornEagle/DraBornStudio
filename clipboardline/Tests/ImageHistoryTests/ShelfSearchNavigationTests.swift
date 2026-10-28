import AppKit
import Carbon
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class ShelfSearchNavigationTests: HistoryTestCase {
    private func wait(_ predicate: () -> Bool) {
        let end = Date().addingTimeInterval(5)
        while !predicate() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(predicate(), "Search navigation fixture did not settle")
    }
    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = [], _ text: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
            isARepeat: false, keyCode: code)!
    }
    private func populate(_ store: LibraryStore, fixture: SyntheticFixture) throws {
        for i in 0..<4 {
            let image = try store.captureImage(fixture.image())
            try store.update(image.id) { $0.note = "navigation image \(i)" }
            fixture.date.addTimeInterval(1)
        }
        for i in 0..<3 {
            _ = try store.captureText("navigation note \(i)")
            fixture.date.addTimeInterval(1)
        }
        for i in 0..<2 {
            _ = try store.captureLink(try XCTUnwrap(URL(string: "https://example.com/navigation/\(i)")))
            fixture.date.addTimeInterval(1)
        }
        // Raw shelf column zero is deliberately absent from the filtered rows.
        // Navigation and callbacks must use displayed results, not raw history.
        _ = try store.captureImage(fixture.image())
        _ = try store.captureText("unrelated synthetic note")
        _ = try store.captureLink(try XCTUnwrap(URL(string: "https://example.com/unrelated")))
    }
    private func search(_ line: Line) {
        line.setPresentation(.all, requestFocus: false)
        line.revealed = true
        line.beginShelfSearch(.images)
        line.updateShelfSearch("navigation", for: .images)
        wait {
            line.displayItems.count == 4 && line.texts.displayEntries.count == 3 &&
                line.links.displayEntries.count == 2 && !line.shelfSearchIsSearching
        }
        line.finishShelfSearchEditing(.images)
    }
    private func assertSingleSelection(_ line: Line, shelf: Shelf, id: UUID, file: StaticString = #filePath, lineNumber: UInt = #line) {
        XCTAssertEqual(line.activeShelf, shelf, file: file, line: lineNumber)
        XCTAssertEqual(line.selectedIDs, shelf == .images ? [id] : [], file: file, line: lineNumber)
        XCTAssertEqual(line.texts.selectedIDs, shelf == .texts ? [id] : [], file: file, line: lineNumber)
        XCTAssertEqual(line.links.selectedIDs, shelf == .links ? [id] : [], file: file, line: lineNumber)
    }

    func testSearchArrowsChangeShelvesPreserveFilteredColumnAndClamp() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(store, fixture: f)
        let line = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false,
            copyImage: { _ in }, copyText: { _ in }, library: store)
        search(line)
        let images = line.displayItems.map(\.id), texts = line.texts.displayEntries.map(\.id), links = line.links.displayEntries.map(\.id)
        let keyboard = LineKeyboard(line: line, onCopy: { _ in }, onPreview: { _ in }, onClose: {})
        line.texts.selectAll(); line.links.selectAll(); line.select(images[3])
        XCTAssertTrue(keyboard.handle(key(125)))
        assertSingleSelection(line, shelf: .texts, id: texts[2])
        XCTAssertEqual(line.texts.focusedID, texts[2], "A shorter destination clamps the displayed column")
        XCTAssertTrue(keyboard.handle(key(125)))
        assertSingleSelection(line, shelf: .links, id: links[1])
        XCTAssertTrue(keyboard.handle(key(125)))
        assertSingleSelection(line, shelf: .links, id: links[1])
        XCTAssertTrue(keyboard.handle(key(126)))
        assertSingleSelection(line, shelf: .texts, id: texts[1])
        XCTAssertTrue(keyboard.handle(key(126)))
        assertSingleSelection(line, shelf: .images, id: images[1])
        XCTAssertTrue(keyboard.handle(key(126)))
        assertSingleSelection(line, shelf: .images, id: images[1])
        XCTAssertTrue(keyboard.handle(key(124)))
        assertSingleSelection(line, shelf: .images, id: images[2])
        XCTAssertTrue(keyboard.handle(key(123)))
        assertSingleSelection(line, shelf: .images, id: images[1])
        XCTAssertEqual(line.presentation, .all, "Boundary navigation never changes row visibility")
    }

    func testVerticalSearchSkipsEmptyRowsAndNeverReopensHiddenRows() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(store, fixture: f)
        let line = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false,
            copyImage: { _ in }, copyText: { _ in }, library: store)
        search(line)
        let images = line.displayItems.map(\.id), links = line.links.displayEntries.map(\.id)
        let keyboard = LineKeyboard(line: line, onCopy: { _ in }, onPreview: { _ in }, onClose: {})
        line.texts.setFavoritesOnly(true)
        wait { line.texts.displayEntries.isEmpty && !line.shelfSearchIsSearching }
        line.select(images[2])
        XCTAssertTrue(keyboard.handle(key(125)))
        assertSingleSelection(line, shelf: .links, id: links[1])
        XCTAssertTrue(keyboard.handle(key(126)))
        assertSingleSelection(line, shelf: .images, id: images[1])
        // An empty focused row still uses its physical position in the stack.
        line.focusShelf(.texts, requestFocus: false)
        XCTAssertTrue(keyboard.handle(key(125)))
        assertSingleSelection(line, shelf: .links, id: links[0])
        line.setPresentation(.both, requestFocus: false)
        line.select(images[1])
        XCTAssertTrue(keyboard.handle(key(125)))
        XCTAssertEqual(line.activeShelf, .images)
        XCTAssertEqual(line.focusedID, images[1])
        XCTAssertEqual(line.presentation, .both, "The hidden link row must not be opened to reach its results")
        line.setFavoritesOnly(true)
        wait { line.displayItems.isEmpty && line.texts.displayEntries.isEmpty && !line.shelfSearchIsSearching }
        XCTAssertTrue(keyboard.handle(key(125)))
        XCTAssertTrue(keyboard.handle(key(126)))
        XCTAssertEqual(line.activeShelf, .images)
        XCTAssertTrue(line.selectedIDs.isEmpty); XCTAssertTrue(line.texts.selectedIDs.isEmpty)
        XCTAssertEqual(line.presentation, .both)
    }

    func testSpacePreviewsAndReturnCopiesOnlyFocusedFilteredResultsAcrossKinds() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(store, fixture: f)
        var imageCopies = [URL](), stringCopies = [String](), imagePreviews = [UUID](), textPreviews = [UUID](), linkPreviews = [UUID]()
        let line = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false,
            copyImage: { imageCopies.append($0) }, copyText: { stringCopies.append($0) }, library: store)
        search(line)
        let image = line.displayItems[1], text = line.texts.displayEntries[1], link = line.links.displayEntries[1]
        let keyboard = LineKeyboard(line: line, onCopy: { line.copyAction($0) }, onPreview: { imagePreviews.append($0) }, onClose: {},
            onTextCopy: { line.texts.copyAction($0) }, onTextPreview: { textPreviews.append($0) }, onLinkPreview: { linkPreviews.append($0) })
        XCTAssertTrue(keyboard.handle(key(124)))
        XCTAssertTrue(keyboard.handle(key(49)))
        XCTAssertTrue(keyboard.handle(key(36)))
        XCTAssertEqual(imagePreviews, [image.id]); XCTAssertEqual(imageCopies, [image.url])
        XCTAssertTrue(keyboard.handle(key(125)))
        XCTAssertTrue(keyboard.handle(key(49)))
        XCTAssertTrue(keyboard.handle(key(36)))
        XCTAssertEqual(textPreviews, [text.id]); XCTAssertEqual(stringCopies, [text.text])
        XCTAssertTrue(keyboard.handle(key(125)))
        XCTAssertTrue(keyboard.handle(key(49)))
        XCTAssertTrue(keyboard.handle(key(36)))
        XCTAssertEqual(linkPreviews, [link.id])
        XCTAssertEqual(stringCopies, [text.text, try XCTUnwrap(link.originalURL)])
        // Copying a link refreshes its recency. Choose the neighboring result
        // from the current order rather than assuming the pre-copy order.
        let copiedIndex = try XCTUnwrap(line.links.displayEntries.firstIndex { $0.id == link.id })
        let neighboringLink = line.links.displayEntries[copiedIndex == 0 ? 1 : copiedIndex - 1]
        XCTAssertTrue(keyboard.handle(key(copiedIndex == 0 ? 124 : 123)))
        XCTAssertTrue(keyboard.handle(key(49)))
        XCTAssertTrue(keyboard.handle(key(76)), "The numeric keypad Enter also copies the focused result")
        XCTAssertEqual(linkPreviews, [link.id, neighboringLink.id])
        XCTAssertEqual(stringCopies, [text.text, try XCTUnwrap(link.originalURL), try XCTUnwrap(neighboringLink.originalURL)])
        XCTAssertTrue(line.isShelfSearchActive); XCTAssertEqual(line.shelfSearchQuery, "navigation")
        XCTAssertEqual(line.presentation, .all)
    }

    func testRemappedVerticalActionsRespectNativeEditingAndKeepOldBehaviorOutsideSearch() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(store, fixture: f)
        let line = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false,
            copyImage: { _ in }, copyText: { _ in }, library: store)
        search(line)
        try line.keyboardBindings.set([KeyShortcut(keyCode: 38, modifiers: 0, keyLabel: "J")], for: .up)
        try line.keyboardBindings.set([KeyShortcut(keyCode: 40, modifiers: 0, keyLabel: "K")], for: .down)
        let images = line.displayItems.map(\.id), texts = line.texts.displayEntries.map(\.id)
        let keyboard = LineKeyboard(line: line, onCopy: { _ in }, onPreview: { _ in }, onClose: {})
        XCTAssertFalse(keyboard.handle(key(125)), "The old arrow binding stops routing after remapping")
        XCTAssertTrue(keyboard.handle(key(40, [], "k")))
        assertSingleSelection(line, shelf: .texts, id: texts[0])
        XCTAssertTrue(keyboard.handle(key(38, [], "j")))
        assertSingleSelection(line, shelf: .images, id: images[0])
        XCTAssertTrue(keyboard.handle(key(125, .shift)))
        XCTAssertEqual(line.activeShelf, .images, "Shift+arrow retains range selection in the current row")
        XCTAssertEqual(line.selectedIDs, Set(images.prefix(2)))
        line.beginShelfSearch(.images)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 100))
        let panel = LinePanel(content: content); panel.keyboardFocusAllowed = true
        let field = ShelfSearchTextField(line: line, shelf: .images)
        field.frame = NSRect(x: 10, y: 10, width: 300, height: 30); content.addSubview(field)
        defer { panel.makeFirstResponder(nil); panel.contentView = nil }
        XCTAssertTrue(panel.makeFirstResponder(field))
        var routed = 0
        panel.onKey = { event in routed += 1; return keyboard.handle(event) }
        XCTAssertFalse(panel.routeKey(key(40, [], "k"), isFocused: true))
        XCTAssertFalse(panel.routeKey(key(49), isFocused: true))
        XCTAssertFalse(panel.routeKey(key(36), isFocused: true))
        XCTAssertFalse(keyboard.handle(key(40, [], "k")))
        XCTAssertEqual(routed, 0); XCTAssertEqual(line.activeShelf, .images)
        line.finishShelfSearchEditing(.images, selectFirst: false)
        XCTAssertTrue(line.closeShelfSearch(requestFocus: false))
        line.cancelSelection(); line.moveSelection(1)
        let rawImages = line.displayItems.map(\.id)
        let rawTexts = line.texts.displayEntries.map(\.id)
        XCTAssertTrue(keyboard.handle(key(40, [], "k")))
        assertSingleSelection(line, shelf: .texts, id: rawTexts[0])
        XCTAssertTrue(keyboard.handle(key(38, [], "j")))
        assertSingleSelection(line, shelf: .images, id: rawImages[0])
    }
}
