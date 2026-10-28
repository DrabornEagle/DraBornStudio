import AppKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class ShelfDefaultNavigationTests: HistoryTestCase {
    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: code)!
    }
    private func populate(_ store: LibraryStore, _ fixture: SyntheticFixture,
                          images: Int = 4, texts: Int = 3, links: Int = 2) throws {
        for index in 0..<images { _ = try store.captureImage(fixture.image(name: "Navigation \(index).png")); fixture.date += 1 }
        for index in 0..<texts { _ = try store.captureText("shelf navigation note \(index)"); fixture.date += 1 }
        for index in 0..<links {
            _ = try store.captureLink(try XCTUnwrap(URL(string: "https://example.com/shelf-navigation/\(index)")))
            fixture.date += 1
        }
    }
    private func line(_ fixture: SyntheticFixture, _ store: LibraryStore) -> Line {
        Line(defaults: fixture.defaults, inbox: fixture.inbox, now: { fixture.date }, breeze: false,
            copyImage: { _ in }, copyText: { _ in }, library: store)
    }
    private func assertSelection(_ line: Line, shelf: Shelf, id: UUID,
                                 file: StaticString = #filePath, lineNumber: UInt = #line) {
        XCTAssertEqual(line.activeShelf, shelf, file: file, line: lineNumber)
        XCTAssertEqual(line.selectedIDs, shelf == .images ? [id] : [], file: file, line: lineNumber)
        XCTAssertEqual(line.texts.selectedIDs, shelf == .texts ? [id] : [], file: file, line: lineNumber)
        XCTAssertEqual(line.links.selectedIDs, shelf == .links ? [id] : [], file: file, line: lineNumber)
        XCTAssertEqual(line.focusedID, shelf == .images ? id : nil, file: file, line: lineNumber)
        XCTAssertEqual(line.texts.focusedID, shelf == .texts ? id : nil, file: file, line: lineNumber)
        XCTAssertEqual(line.links.focusedID, shelf == .links ? id : nil, file: file, line: lineNumber)
    }

    func testOpeningAllShelvesPrefersOnlyFirstImageAndReopeningResets() throws {
        let fixture = try SyntheticFixture(); defer { fixture.cleanup() }
        let store = try LibraryStore(defaults: fixture.defaults, inbox: fixture.inbox, now: { fixture.date })
        try populate(store, fixture)
        let line = line(fixture, store)
        line.setPresentation(.all, requestFocus: false)
        line.focusShelf(.links, requestFocus: false)
        line.selectAll(); line.texts.selectAll(); line.links.selectAll()
        var focusRequests = 0; line.onFocusRequested = { focusRequests += 1 }
        line.revealed = true
        let image = try XCTUnwrap(line.displayItems.first?.id)
        assertSelection(line, shelf: .images, id: image)
        let keyboard = LineKeyboard(line: line, onCopy: { _ in }, onPreview: { _ in }, onClose: {})
        XCTAssertTrue(keyboard.handle(key(124)))
        XCTAssertTrue(keyboard.handle(key(125)))
        XCTAssertEqual(line.activeShelf, .texts)
        line.revealed = false
        XCTAssertTrue(line.selectedIDs.isEmpty); XCTAssertTrue(line.texts.selectedIDs.isEmpty); XCTAssertTrue(line.links.selectedIDs.isEmpty)
        line.selectAll(); line.texts.selectAll(); line.links.selectAll()
        line.revealed = true
        assertSelection(line, shelf: .images, id: image)
        XCTAssertEqual(line.presentation, .all)
        XCTAssertEqual(focusRequests, 0, "Selection reset and row arrows do not steal native editor focus")
    }

    func testOpeningWithImagesHiddenSelectsFirstNonemptyVisibleShelf() throws {
        let fixture = try SyntheticFixture(); defer { fixture.cleanup() }
        let store = try LibraryStore(defaults: fixture.defaults, inbox: fixture.inbox, now: { fixture.date })
        try populate(store, fixture)
        let line = line(fixture, store)
        for presentation in [ShelfPresentation.textsLinks, .texts, .links] {
            line.revealed = false
            line.setPresentation(presentation, requestFocus: false)
            line.selectAll(); line.texts.selectAll(); line.links.selectAll()
            line.revealed = true
            if presentation == .links { assertSelection(line, shelf: .links, id: try XCTUnwrap(line.links.displayEntries.first?.id)) }
            else { assertSelection(line, shelf: .texts, id: try XCTUnwrap(line.texts.displayEntries.first?.id)) }
            XCTAssertEqual(line.presentation, presentation, "Opening must not reveal the hidden image shelf")
        }
    }

    func testOpeningSkipsEmptyAndFilteredShelvesWithoutInventingSelection() throws {
        let fixture = try SyntheticFixture(); defer { fixture.cleanup() }
        let store = try LibraryStore(defaults: fixture.defaults, inbox: fixture.inbox, now: { fixture.date })
        try populate(store, fixture, images: 0)
        let line = line(fixture, store)
        line.setPresentation(.all, requestFocus: false); line.revealed = true
        assertSelection(line, shelf: .texts, id: try XCTUnwrap(line.texts.displayEntries.first?.id))
        line.revealed = false; line.texts.setFavoritesOnly(true); line.revealed = true
        XCTAssertTrue(line.texts.displayEntries.isEmpty)
        assertSelection(line, shelf: .links, id: try XCTUnwrap(line.links.displayEntries.first?.id))
        line.revealed = false; line.links.setFavoritesOnly(true); line.revealed = true
        XCTAssertEqual(line.activeShelf, .images)
        XCTAssertTrue(line.selectedIDs.isEmpty); XCTAssertNil(line.focusedID)
        XCTAssertTrue(line.texts.selectedIDs.isEmpty); XCTAssertNil(line.texts.focusedID)
        XCTAssertTrue(line.links.selectedIDs.isEmpty); XCTAssertNil(line.links.focusedID)
        XCTAssertTrue(line.texts.favoritesOnly); XCTAssertTrue(line.links.favoritesOnly)
    }

    func testFilteredIncomingScreenshotKeepsFirstTextFallbackSelected() throws {
        let fixture = try SyntheticFixture(); defer { fixture.cleanup() }
        let store = try LibraryStore(defaults: fixture.defaults, inbox: fixture.inbox, now: { fixture.date })
        try populate(store, fixture, images: 1)
        let line = line(fixture, store)
        line.setPresentation(.all, requestFocus: false); line.setFavoritesOnly(true)
        line.revealed = true
        let text = try XCTUnwrap(line.texts.displayEntries.first?.id)
        XCTAssertTrue(line.displayItems.isEmpty); XCTAssertFalse(line.links.displayEntries.isEmpty)
        assertSelection(line, shelf: .texts, id: text)

        // The screenshot arrival follows initial reveal. Its unpinned image is
        // stored normally but remains outside the visible favorites-only row.
        let screenshot = try fixture.image(name: "Filtered incoming screenshot.png")
        let image = try XCTUnwrap(line.hang(screenshot, quietly: true))
        XCTAssertTrue(line.items.contains { $0.id == image })
        XCTAssertFalse(try XCTUnwrap(store.item(image)).favorite)
        XCTAssertTrue(line.displayItems.isEmpty)
        line.selectFirstShelfItems(line.presentation.shelves)
        assertSelection(line, shelf: .texts, id: text)
        XCTAssertTrue(line.favoritesOnly); XCTAssertEqual(line.presentation, .all)
    }

    func testClosedPreviewVerticalArrowsPreserveColumnClampAndClearOtherSelections() throws {
        let fixture = try SyntheticFixture(); defer { fixture.cleanup() }
        let store = try LibraryStore(defaults: fixture.defaults, inbox: fixture.inbox, now: { fixture.date })
        try populate(store, fixture)
        let line = line(fixture, store)
        line.setPresentation(.all, requestFocus: false); line.revealed = true
        let images = line.displayItems.map(\.id), texts = line.texts.displayEntries.map(\.id), links = line.links.displayEntries.map(\.id)
        let keyboard = LineKeyboard(line: line, onCopy: { _ in }, onPreview: { _ in }, onClose: {})
        line.select(images[3]); line.texts.selectAll(); line.links.selectAll()
        XCTAssertTrue(keyboard.handle(key(125))); assertSelection(line, shelf: .texts, id: texts[2])
        XCTAssertTrue(keyboard.handle(key(125))); assertSelection(line, shelf: .links, id: links[1])
        XCTAssertTrue(keyboard.handle(key(125))); assertSelection(line, shelf: .links, id: links[1])
        XCTAssertTrue(keyboard.handle(key(126))); assertSelection(line, shelf: .texts, id: texts[1])
        XCTAssertTrue(keyboard.handle(key(126))); assertSelection(line, shelf: .images, id: images[1])
        XCTAssertTrue(keyboard.handle(key(126))); assertSelection(line, shelf: .images, id: images[1])
        XCTAssertTrue(keyboard.handle(key(123))); assertSelection(line, shelf: .images, id: images[0])
        XCTAssertTrue(keyboard.handle(key(124))); assertSelection(line, shelf: .images, id: images[1])
        XCTAssertEqual(line.presentation, .all); XCTAssertFalse(line.isShelfSearchActive)
    }

    func testClosedPreviewVerticalArrowsSkipEmptyAndHiddenShelves() throws {
        let fixture = try SyntheticFixture(); defer { fixture.cleanup() }
        let store = try LibraryStore(defaults: fixture.defaults, inbox: fixture.inbox, now: { fixture.date })
        try populate(store, fixture)
        let line = line(fixture, store)
        line.setPresentation(.all, requestFocus: false); line.revealed = true
        line.texts.setFavoritesOnly(true)
        let images = line.displayItems.map(\.id), links = line.links.displayEntries.map(\.id)
        let keyboard = LineKeyboard(line: line, onCopy: { _ in }, onPreview: { _ in }, onClose: {})
        line.select(images[2])
        XCTAssertTrue(keyboard.handle(key(125))); assertSelection(line, shelf: .links, id: links[1])
        XCTAssertTrue(keyboard.handle(key(126))); assertSelection(line, shelf: .images, id: images[1])
        line.setPresentation(.both, requestFocus: false)
        XCTAssertTrue(keyboard.handle(key(125))); assertSelection(line, shelf: .images, id: images[1])
        XCTAssertEqual(line.presentation, .both, "The hidden link shelf remains hidden")
        line.setFavoritesOnly(true)
        XCTAssertTrue(keyboard.handle(key(125))); XCTAssertTrue(keyboard.handle(key(126)))
        XCTAssertTrue(line.selectedIDs.isEmpty); XCTAssertTrue(line.texts.selectedIDs.isEmpty)
        XCTAssertEqual(line.presentation, .both)
    }

    func testClosedPreviewSpaceAndEnterRouteNewActiveShelfWithoutClipboardAccess() throws {
        let fixture = try SyntheticFixture(); defer { fixture.cleanup() }
        let store = try LibraryStore(defaults: fixture.defaults, inbox: fixture.inbox, now: { fixture.date })
        try populate(store, fixture)
        let line = line(fixture, store)
        line.setPresentation(.all, requestFocus: false); line.revealed = true
        let image = try XCTUnwrap(line.displayItems.first?.id), text = line.texts.displayEntries[1].id, link = line.links.displayEntries[1].id
        var previews = [String](), copiedIDs = [[UUID]](), legacyCopies = 0
        let keyboard = LineKeyboard(line: line, onCopy: { _ in legacyCopies += 1 },
            onPreview: { previews.append("images:\($0)") }, onClose: {},
            onTextCopy: { _ in legacyCopies += 1 },
            onTextPreview: { previews.append("texts:\($0)") }, onLinkPreview: { previews.append("links:\($0)") },
            onCopyAndClose: { copiedIDs.append(line.activeActionIDs) })
        XCTAssertTrue(keyboard.handle(key(49))); XCTAssertTrue(keyboard.handle(key(36)))
        XCTAssertTrue(keyboard.handle(key(125))); XCTAssertTrue(keyboard.handle(key(124)))
        XCTAssertTrue(keyboard.handle(key(49))); XCTAssertTrue(keyboard.handle(key(36)))
        XCTAssertTrue(keyboard.handle(key(125)))
        XCTAssertTrue(keyboard.handle(key(49))); XCTAssertTrue(keyboard.handle(key(76)))
        XCTAssertEqual(previews, ["images:\(image)", "texts:\(text)", "links:\(link)"])
        XCTAssertEqual(copiedIDs, [[image], [text], [link]])
        XCTAssertEqual(legacyCopies, 0, "Return must use the shared copy-and-close route")
    }

    func testSearchEditingKeepsVerticalAndPreviewCopyKeysNative() throws {
        let fixture = try SyntheticFixture(); defer { fixture.cleanup() }
        let store = try LibraryStore(defaults: fixture.defaults, inbox: fixture.inbox, now: { fixture.date })
        try populate(store, fixture)
        let line = line(fixture, store)
        line.setPresentation(.all, requestFocus: false); line.revealed = true
        var actions = 0
        let keyboard = LineKeyboard(line: line, onCopy: { _ in actions += 1 }, onPreview: { _ in actions += 1 },
            onClose: {}, onTextCopy: { _ in actions += 1 }, onTextPreview: { _ in actions += 1 },
            onLinkPreview: { _ in actions += 1 }, onCopyAndClose: { actions += 1 })
        line.beginShelfSearch(.images)
        let selection = line.selectedIDs
        let nativeKeys: [UInt16] = [125, 126, 123, 124, 49, 36]
        for code in nativeKeys { XCTAssertFalse(keyboard.handle(key(code))) }
        XCTAssertEqual(line.searchEditingShelf, .images); XCTAssertEqual(line.activeShelf, .images)
        XCTAssertEqual(line.selectedIDs, selection); XCTAssertEqual(actions, 0)
    }
}
