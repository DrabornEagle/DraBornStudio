import AppKit
import Carbon
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class ShelfPagingTests: HistoryTestCase {
    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = [], _ text: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
            isARepeat: false, keyCode: code)!
    }
    private func resetLayout() { Layout.size = .medium; Layout.maximumRowHeight = .greatestFiniteMagnitude }
    private func populate(_ f: SyntheticFixture, store: LibraryStore, count: Int) throws {
        for index in 0..<count {
            let image = try store.captureImage(f.image())
            try store.update(image.id) { $0.note = "pagingmatch image \(index)" }
            _ = try store.captureText("pagingmatch text \(index)")
            _ = try store.captureLink(try XCTUnwrap(URL(string: "https://example.com/pagingmatch/\(index)")))
            f.date.addTimeInterval(1)
        }
    }
    private func line(_ f: SyntheticFixture, store: LibraryStore, width: CGFloat) -> Line {
        let line = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false,
            copyImage: { _ in }, copyText: { _ in }, library: store)
        line.setPresentation(.all, requestFocus: false); line.setViewportWidth(width)
        return line
    }
    private func keyboard(_ line: Line) -> LineKeyboard {
        LineKeyboard(line: line, onCopy: { _ in }, onPreview: { _ in }, onClose: {})
    }
    private func ids(_ line: Line, _ shelf: Shelf) -> [UUID] {
        switch shelf {
        case .images: line.displayItems.map(\.id)
        case .texts: line.texts.displayEntries.map(\.id)
        case .links: line.links.displayEntries.map(\.id)
        }
    }
    private func focus(_ line: Line, _ shelf: Shelf) -> UUID? {
        switch shelf { case .images: line.focusedID; case .texts: line.texts.focusedID; case .links: line.links.focusedID }
    }
    private func offset(_ line: Line, _ shelf: Shelf) -> CGFloat {
        switch shelf { case .images: line.scrollOffset; case .texts: line.texts.scrollOffset; case .links: line.links.scrollOffset }
    }
    private func scroll(_ line: Line, _ shelf: Shelf, to value: CGFloat) {
        switch shelf {
        case .images: line.setScrollOffset(value)
        case .texts: line.texts.scroll(line.texts.scrollOffset - value, width: line.viewportWidth)
        case .links: line.links.scroll(line.links.scrollOffset - value, width: line.viewportWidth)
        }
    }
    private func select(_ id: UUID, _ line: Line, _ shelf: Shelf, toggle: Bool = false) {
        line.focusShelf(shelf, requestFocus: false)
        switch shelf {
        case .images: line.select(id, toggle: toggle)
        case .texts: line.texts.select(id, toggle: toggle, width: line.viewportWidth)
        case .links: line.links.select(id, toggle: toggle, width: line.viewportWidth)
        }
    }
    private func wait(_ predicate: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !predicate() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(predicate(), "Shelf paging fixture did not settle")
    }

    func testOptionArrowsPageNumberedGroupsPreserveSlotAndOnlyChangeActiveShelf() throws {
        resetLayout(); let f = try SyntheticFixture(); defer { f.cleanup(); resetLayout() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(f, store: store, count: 23)
        let line = line(f, store: store, width: 1800), keyboard = keyboard(line)
        for shelf in Shelf.allCases {
            let values = ids(line, shelf)
            select(values[2], line, shelf); select(values[3], line, shelf, toggle: true)
            let otherRows = Shelf.allCases.filter { $0 != shelf }
            let otherOffsets = otherRows.map { offset(line, $0) }, otherFocus = otherRows.map { focus(line, $0) }
            XCTAssertEqual(line.activeIDs.count, 2)
            XCTAssertEqual(line.quickSelectionIDs, Array(values[0..<9]))
            XCTAssertTrue(keyboard.handle(key(124, .option)))
            XCTAssertEqual(line.quickSelectionIDs, Array(values[9..<18]))
            XCTAssertEqual(focus(line, shelf), values[12], "Paging keeps the focused fourth slot")
            XCTAssertEqual(line.activeIDs, [values[12]], "A page jump starts a single selection")
            XCTAssertTrue(keyboard.handle(key(123, .option)))
            XCTAssertEqual(line.quickSelectionIDs, Array(values[0..<9]))
            XCTAssertEqual(focus(line, shelf), values[3])
            XCTAssertEqual(otherRows.map { offset(line, $0) }, otherOffsets)
            XCTAssertEqual(otherRows.map { focus(line, $0) }, otherFocus)
            XCTAssertEqual(line.activeShelf, shelf); XCTAssertEqual(line.presentation, .all)
        }
    }

    func testNarrowPagesAndPartialLastPageRemainNumberedWithoutWrapping() throws {
        resetLayout(); let f = try SyntheticFixture(); defer { f.cleanup(); resetLayout() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(f, store: store, count: 11)
        let line = line(f, store: store, width: 720), keyboard = keyboard(line)
        for shelf in Shelf.allCases {
            line.focusShelf(shelf, requestFocus: false)
            let values = ids(line, shelf)
            XCTAssertEqual(line.quickSelectionIDs, Array(values[0..<4]))
            XCTAssertTrue(keyboard.handle(key(124, .option)))
            XCTAssertEqual(line.quickSelectionIDs, Array(values[4..<8]))
            XCTAssertEqual(focus(line, shelf), values[4], "No prior selection starts at the destination's first slot")
            XCTAssertTrue(keyboard.handle(key(21, [], "4")))
            XCTAssertEqual(focus(line, shelf), values[7])
            XCTAssertTrue(keyboard.handle(key(124, .option)))
            XCTAssertEqual(line.quickSelectionIDs, Array(values[8..<11]))
            XCTAssertEqual(focus(line, shelf), values[10], "A missing fourth slot clamps to the partial page's final item")
            let lastOffset = offset(line, shelf)
            XCTAssertTrue(keyboard.handle(key(124, .option)))
            XCTAssertEqual(line.quickSelectionIDs, Array(values[8..<11]))
            XCTAssertEqual(focus(line, shelf), values[10]); XCTAssertEqual(offset(line, shelf), lastOffset)
            XCTAssertTrue(keyboard.handle(key(20, [], "3")))
            XCTAssertEqual(focus(line, shelf), values[10], "Number 3 selects the final partial-page card")
            XCTAssertTrue(keyboard.handle(key(123, .option)))
            XCTAssertEqual(line.quickSelectionIDs, Array(values[4..<8])); XCTAssertEqual(focus(line, shelf), values[6])
            XCTAssertTrue(keyboard.handle(key(123, .option)))
            XCTAssertEqual(line.quickSelectionIDs, Array(values[0..<4])); XCTAssertEqual(focus(line, shelf), values[2])
            XCTAssertTrue(keyboard.handle(key(123, .option)))
            XCTAssertEqual(focus(line, shelf), values[2]); XCTAssertEqual(line.quickSelectionIDs, Array(values[0..<4]))
        }
    }

    func testWidePagesWorkWithoutScrollAndResizeOrManualScrollRebasesNumbering() throws {
        resetLayout(); let f = try SyntheticFixture(); defer { f.cleanup(); resetLayout() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(f, store: store, count: 15)
        let line = line(f, store: store, width: 10000), keyboard = keyboard(line)
        for shelf in Shelf.allCases {
            line.setViewportWidth(10000); line.focusShelf(shelf, requestFocus: false); scroll(line, shelf, to: 0)
            let values = ids(line, shelf)
            XCTAssertTrue(keyboard.handle(key(124, .option)))
            XCTAssertEqual(line.quickSelectionIDs, Array(values[9..<15])); XCTAssertEqual(focus(line, shelf), values[9])
            XCTAssertEqual(offset(line, shelf), 0, "Numbered pages still advance when all cards physically fit")
            XCTAssertTrue(keyboard.handle(key(123, .option)))
            XCTAssertEqual(line.quickSelectionIDs, Array(values[0..<9])); XCTAssertEqual(focus(line, shelf), values[0])
            line.setViewportWidth(720)
            XCTAssertEqual(line.quickSelectionIDs, Array(values[0..<4]))
            XCTAssertTrue(keyboard.handle(key(124, .option)))
            XCTAssertEqual(line.quickSelectionIDs, Array(values[4..<8]))
            scroll(line, shelf, to: Layout.spacing * 2)
            XCTAssertEqual(line.quickSelectionIDs, Array(values[2..<6]), "A deliberate wheel position replaces the prior page anchor")
            XCTAssertTrue(keyboard.handle(key(124, .option)))
            XCTAssertEqual(line.quickSelectionIDs, Array(values[6..<10]))
        }
    }

    func testPagesUseOnlySearchAndPinnedResultsOfTheActiveShelf() throws {
        resetLayout(); let f = try SyntheticFixture(); defer { f.cleanup(); resetLayout() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(f, store: store, count: 18)
        _ = try store.captureImage(f.image()); _ = try store.captureText("Unrelated text")
        _ = try store.captureLink(try XCTUnwrap(URL(string: "https://example.com/unrelated")))
        let line = line(f, store: store, width: 720), keyboard = keyboard(line)
        for shelf in Shelf.allCases {
            let matches = Array(ids(line, shelf).dropFirst())
            try store.toggleFavorite(matches.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element))
        }
        line.beginShelfSearch(.images); line.updateShelfSearch("pagingmatch", for: .images)
        wait { !line.shelfSearchIsSearching && line.shelfSearchResultCount == 54 }
        line.finishShelfSearchEditing(.images, selectFirst: false)
        for shelf in Shelf.allCases {
            line.focusShelf(shelf, requestFocus: false); line.setActiveFavorites(true)
            wait { !line.shelfSearchIsSearching && self.ids(line, shelf).count == 9 }
            let visible = ids(line, shelf)
            XCTAssertTrue(keyboard.handle(key(124, .option)))
            XCTAssertEqual(line.quickSelectionIDs, Array(visible[4..<8]))
            XCTAssertTrue(line.quickSelectionIDs.allSatisfy { visible.contains($0) })
            XCTAssertTrue(keyboard.handle(key(124, .option)))
            XCTAssertEqual(line.quickSelectionIDs, [visible[8]]); XCTAssertEqual(focus(line, shelf), visible[8])
        }
        XCTAssertEqual(line.shelfSearchQuery, "pagingmatch"); XCTAssertEqual(line.presentation, .all)
    }

    func testFallingImagesKeepTheirVisualColumnsAndCannotReceivePageFocus() throws {
        resetLayout(); let f = try SyntheticFixture(); defer { f.cleanup(); resetLayout() }
        let line = f.line(); line.setViewportWidth(720)
        for _ in 0..<10 { line.hang(try f.image(owned: false), quietly: true) }
        let original = line.displayItems.map(\.id), keyboard = keyboard(line)
        line.drop(original[1], quietly: true); line.select(original[0])
        XCTAssertTrue(line.displayItems[1].falling)
        XCTAssertTrue(keyboard.handle(key(124, .option)))
        XCTAssertEqual(line.quickSelectionIDs, Array(original[4..<8]), "A falling first-page card cannot shift later visual page columns")
        XCTAssertFalse(line.activeIDs.contains(original[1]))
        XCTAssertTrue(keyboard.handle(key(123, .option)))
        XCTAssertEqual(line.quickSelectionIDs, [original[0], original[2], original[3]])
        XCTAssertFalse(line.activeIDs.contains(original[1]))
    }

    func testPagingDefaultsCanBeRemappedAndDoNotTakeOverOlderOverridesOrSearchEditing() throws {
        resetLayout(); let f = try SyntheticFixture(); defer { f.cleanup(); resetLayout() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(f, store: store, count: 12)
        let line = line(f, store: store, width: 720), keyboard = keyboard(line), bindings = line.keyboardBindings
        for context in [KeyboardContext.line, .imagePreview, .textPreview, .linkPreview] {
            XCTAssertEqual(bindings.action(for: key(123, .option), in: context), .previousPage)
            XCTAssertEqual(bindings.action(for: key(124, .option), in: context), .nextPage)
        }
        XCTAssertEqual(bindings.action(for: key(124, .option), in: .library), .nextPage)
        let legacy = ["next": [KeyShortcut(keyCode: 124, modifiers: optionKey, keyLabel: "→")]]
        f.defaults.set(try JSONEncoder().encode(legacy), forKey: "contextKeyboardBindingsV1")
        XCTAssertEqual(bindings.action(for: key(124, .option), in: .line), .next)
        try bindings.reset(.next)
        try bindings.set([KeyShortcut(keyCode: 116, modifiers: controlKey, keyLabel: "Page ↑")], for: .previousPage)
        try bindings.set([KeyShortcut(keyCode: 121, modifiers: controlKey, keyLabel: "Page ↓")], for: .nextPage)
        XCTAssertFalse(keyboard.handle(key(123, .option))); XCTAssertFalse(keyboard.handle(key(124, .option)))
        let values = ids(line, .images)
        XCTAssertTrue(keyboard.handle(key(121, .control))); XCTAssertEqual(focus(line, .images), values[4])
        XCTAssertTrue(keyboard.handle(key(116, .control))); XCTAssertEqual(focus(line, .images), values[0])
        line.beginShelfSearch(.images)
        XCTAssertFalse(keyboard.handle(key(121, .control))); XCTAssertFalse(keyboard.handle(key(116, .control)))
        XCTAssertEqual(focus(line, .images), values[0], "Search typing keeps native navigation")
        try bindings.reset(.nextPage)
        XCTAssertEqual(bindings.action(for: key(124, .option), in: .line), .nextPage)
    }

    func testPreviewPagesKeepOneWindowAndNativeTextWordNavigationWhileEditing() throws {
        _ = NSApplication.shared
        resetLayout(); let f = try SyntheticFixture(); defer { f.cleanup(); resetLayout() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populate(f, store: store, count: 14)
        let line = line(f, store: store, width: 720), app = AppDelegate(line: line, watchesFiles: false)
        var sharedWindow: NSWindow?
        defer { app.previewWindow?.close() }
        for shelf in Shelf.allCases {
            scroll(line, shelf, to: 0)
            let values = ids(line, shelf)
            switch shelf {
            case .images: app.showPreview(values[1])
            case .texts: app.showTextPreview(values[1])
            case .links: app.showLinkPreview(values[1])
            }
            let panel = try XCTUnwrap(app.previewWindow)
            if let sharedWindow { XCTAssertTrue(panel === sharedWindow) } else { sharedWindow = panel }
            XCTAssertTrue(panel.onKey?(key(124, .option)) ?? false)
            XCTAssertEqual(app.previewSession?.currentID, values[5]); XCTAssertEqual(focus(line, shelf), values[5])
            XCTAssertEqual(line.quickSelectionIDs, Array(values[4..<8]))
            XCTAssertTrue(app.previewWindow === panel); XCTAssertTrue(panel.isVisible)
            XCTAssertTrue(panel.onKey?(key(123, .option)) ?? false)
            XCTAssertEqual(app.previewSession?.currentID, values[1]); XCTAssertTrue(app.previewWindow === panel)
            if shelf == .texts {
                let text = try XCTUnwrap(app.textPreview)
                text.beginEditing(); text.textView.string = "pagingmatch edited text İstanbul"
                text.textDidChange(Notification(name: NSText.didChangeNotification, object: text.textView))
                XCTAssertFalse(panel.onKey?(key(123, .option)) ?? false)
                XCTAssertFalse(panel.onKey?(key(124, .option)) ?? false)
                XCTAssertTrue(text.isEditing); XCTAssertEqual(app.previewSession?.currentID, values[1])
                XCTAssertTrue(panel.onKey?(key(36, .command)) ?? false)
                XCTAssertFalse(text.isEditing)
                XCTAssertTrue(panel.onKey?(key(124, .option)) ?? false)
                XCTAssertEqual(app.previewSession?.currentID, values[5]); XCTAssertTrue(app.previewWindow === panel)
                XCTAssertEqual(try store.item(values[1])?.text, "pagingmatch edited text İstanbul")
            }
        }
    }

    func testEmptyAndSingleItemRowsDoNotWrapAndCommandArrowBoundariesStillWork() throws {
        resetLayout(); let f = try SyntheticFixture(); defer { f.cleanup(); resetLayout() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        let line = line(f, store: store, width: 720), keyboard = keyboard(line)
        for shelf in Shelf.allCases {
            line.focusShelf(shelf, requestFocus: false)
            XCTAssertTrue(keyboard.handle(key(123, .option))); XCTAssertTrue(keyboard.handle(key(124, .option)))
            XCTAssertNil(focus(line, shelf)); XCTAssertTrue(line.activeIDs.isEmpty)
        }
        let only = try XCTUnwrap(store.captureText("Only text"))
        line.focusShelf(.texts, requestFocus: false)
        XCTAssertTrue(keyboard.handle(key(124, .command))); XCTAssertEqual(line.texts.focusedID, only.id)
        XCTAssertTrue(keyboard.handle(key(123, .option))); XCTAssertTrue(keyboard.handle(key(124, .option)))
        XCTAssertEqual(line.quickSelectionIDs, [only.id]); XCTAssertEqual(line.activeIDs, [only.id])
        try populate(f, store: store, count: 12)
        let texts = ids(line, .texts)
        XCTAssertTrue(keyboard.handle(key(123, .command))); XCTAssertEqual(line.texts.focusedID, texts.first)
        XCTAssertTrue(keyboard.handle(key(124, .command))); XCTAssertEqual(line.texts.focusedID, texts.last)
        XCTAssertTrue(keyboard.handle(key(123, .command))); XCTAssertEqual(line.texts.focusedID, texts.first)
        XCTAssertTrue(keyboard.handle(key(124, .option)))
        XCTAssertEqual(line.quickSelectionIDs, Array(texts[4..<8])); XCTAssertEqual(line.texts.focusedID, texts[4])
    }
}
