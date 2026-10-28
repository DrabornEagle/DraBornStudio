import AppKit
import Carbon
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class RequestedUXTests: HistoryTestCase {
    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = [], _ text: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
    }
    private func wait(_ predicate: () -> Bool) {
        let deadline = Date().addingTimeInterval(4)
        while !predicate() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
        XCTAssertTrue(predicate())
    }
    func testBackspaceUndoesWholeShelfRemovalBatchesWithoutLosingLaterEdits() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        let first = try XCTUnwrap(store.captureText("saved note")), second = try XCTUnwrap(store.captureText("temporary note"))
        let link = try store.captureLink(URL(string: "https://example.com/undo")!)
        let folder = try store.createCollection("Notes"); try store.pin([first.id], to: folder)
        let line = Line(defaults: f.defaults, inbox: f.inbox, breeze: false, library: store)
        let keyboard = LineKeyboard(line: line, onCopy: { _ in }, onPreview: { _ in }, onClose: {})
        line.focusShelf(.texts, requestFocus: false); line.texts.selectAll()
        XCTAssertTrue(keyboard.handle(key(1, [], "s"))); XCTAssertTrue(line.texts.entries.isEmpty)
        try store.update(first.id) { $0.text = "edited while hidden"; $0.note = "keep this" }
        line.focusShelf(.links, requestFocus: false); line.links.select(link.id, width: 1000)
        XCTAssertTrue(keyboard.handle(key(1, [], "s"))); XCTAssertTrue(line.links.entries.isEmpty)
        XCTAssertTrue(keyboard.handle(key(51))); XCTAssertTrue(try store.item(link.id)?.onShelf == true)
        XCTAssertFalse(try store.item(second.id)?.onShelf == true)
        XCTAssertTrue(keyboard.handle(key(51))); XCTAssertEqual(line.texts.entries.count, 2)
        let restored = try XCTUnwrap(store.item(first.id))
        XCTAssertEqual(restored.text, "edited while hidden"); XCTAssertEqual(restored.note, "keep this")
        XCTAssertEqual(restored.createdAt, first.createdAt); XCTAssertTrue(restored.favorite)
        XCTAssertEqual(try store.collections(for: first.id).map(\.id), [folder])
        XCTAssertNil(try store.item(second.id)?.deletedAt); XCTAssertTrue(try store.undoShelfRemoval().isEmpty)
        try store.removeFromShelf([second.id]); try store.trash([second.id])
        XCTAssertTrue(try store.undoShelfRemoval().isEmpty); XCTAssertTrue(try store.item(second.id)?.deletedAt != nil)
        XCTAssertEqual(line.keyboardBindings.action(for: key(51), in: .line), .undoRemoveFromLine)
        XCTAssertEqual(line.keyboardBindings.action(for: key(51), in: .library), .undoTrash)
        XCTAssertEqual(line.keyboardBindings.action(for: key(117), in: .line), .trash)
        let preview = TextPreview(text: "editing", keyboardBindings: line.keyboardBindings); defer { preview.window.close() }
        preview.beginEditing(); XCTAssertFalse(preview.routeKey(key(51)))
    }
    func testShiftShelfTogglesPersistLayoutAndLastShelfClosesLine() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let line = f.line(); line.setPresentation(.all, requestFocus: false)
        var closes = 0
        let keyboard = LineKeyboard(line: line, onCopy: { _ in }, onPreview: { _ in }, onClose: { closes += 1 })
        XCTAssertTrue(keyboard.handle(key(37, .shift, "l"))); XCTAssertEqual(line.presentation, .both)
        XCTAssertTrue(keyboard.handle(key(17, .shift, "t"))); XCTAssertEqual(line.presentation, .images)
        XCTAssertTrue(keyboard.handle(key(34, .shift, "i"))); XCTAssertEqual(closes, 1)
        XCTAssertTrue(keyboard.handle(key(37, .shift, "l"))); XCTAssertEqual(line.presentation, .imagesLinks)
        XCTAssertTrue(keyboard.handle(key(34, .shift, "i"))); XCTAssertEqual(line.presentation, .links)
        XCTAssertEqual(f.line().presentation, .links)
        XCTAssertNil(line.keyboardBindings.action(for: key(37, .shift, "l"), in: .textPreview))
        try line.keyboardBindings.set([KeyShortcut(keyCode: 40, modifiers: shiftKey, keyLabel: "K")], for: .toggleLinks)
        XCTAssertFalse(keyboard.handle(key(37, .shift, "l")))
        XCTAssertTrue(keyboard.handle(key(40, .shift, "k"))); XCTAssertEqual(closes, 2)
    }
    func testFolderPickerCancelsAndPinsMixedSnapshotAtomicallyWithArrowAndEnter() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let original = try f.image(owned: false), image = try store.captureImage(original)
        let text = try XCTUnwrap(store.captureText("folder picker note")), link = try store.captureLink(URL(string: "https://example.com/folder")!)
        let parent = try store.createCollection("A parent"), child = try store.createCollection("B child", parent: parent)
        let ids = [image.id, text.id, link.id]
        let cancelled = try PinFolderPicker(store: store, ids: ids)
        XCTAssertTrue(cancelled.handle(key(53)))
        XCTAssertFalse(try store.item(text.id)?.favorite == true); XCTAssertTrue(try store.collections(for: text.id).isEmpty)
        let picker = try PinFolderPicker(store: store, ids: ids); defer { picker.window.close() }
        XCTAssertEqual(picker.choices[0].id, parent)
        XCTAssertTrue(picker.handle(key(125))); XCTAssertEqual(picker.choices[picker.table.selectedRow].id, child)
        XCTAssertTrue(picker.handle(key(36)))
        for id in ids { XCTAssertTrue(try store.item(id)?.favorite == true); XCTAssertEqual(try store.collections(for: id).map(\.id), [child]) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertFalse(try store.item(image.id)?.path == original.path)
        try store.pin(ids, to: child); XCTAssertTrue(try store.item(text.id)?.favorite == true)
        let unpinned = try XCTUnwrap(store.captureText("must stay unpinned"))
        var failed = false; do { try store.pin([unpinned.id, UUID()], to: child) } catch { failed = true }
        XCTAssertTrue(failed); XCTAssertFalse(try store.item(unpinned.id)?.favorite == true)
        XCTAssertTrue(try store.collections(for: unpinned.id).isEmpty)
        let line = Line(defaults: f.defaults, inbox: f.inbox, breeze: false, library: store)
        line.focusShelf(.texts, requestFocus: false); line.texts.selectAll()
        var snapshot = [UUID](); line.onPinToFolderRequested = { snapshot = $0 }
        let keyboard = LineKeyboard(line: line, onCopy: { _ in }, onPreview: { _ in }, onClose: {})
        XCTAssertTrue(keyboard.handle(key(35, .shift, "p"))); XCTAssertEqual(Set(snapshot), line.texts.selectedIDs)
        line.texts.cancelSelection(); XCTAssertFalse(snapshot.isEmpty)
        let model = LibraryModel(store: store); model.changeScope(.saved); wait { model.ids.count == 3 }
        model.selectAll(); model.onPinToFolderRequested = { snapshot = $0 }
        XCTAssertFalse(model.handleKey(key(35, .shift, "p"), editing: true))
        XCTAssertTrue(model.handleKey(key(35, .shift, "p"), editing: false)); XCTAssertEqual(Set(snapshot), Set(model.ids))
    }
    func testYouTubeBlackPaddingIsRemovedWhileRealFourThreeAndOtherLinksStayIntact() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        func thumbnail(padded: Bool) throws -> NSImage {
            let context = try XCTUnwrap(CGContext(data: nil, width: 480, height: 360, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(NSColor.black.cgColor); context.fill(CGRect(x: 0, y: 0, width: 480, height: 360))
            context.setFillColor(NSColor.systemTeal.cgColor); context.fill(CGRect(x: 0, y: padded ? 45 : 0, width: 480, height: padded ? 270 : 360))
            return NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: NSSize(width: 480, height: 360))
        }
        let padded = try thumbnail(padded: true), real = try thumbnail(padded: false)
        XCTAssertEqual(LinkThumbnail.removingYouTubeLetterbox(padded).size, NSSize(width: 480, height: 270))
        XCTAssertEqual(LinkThumbnail.removingYouTubeLetterbox(real).size, NSSize(width: 480, height: 360))
        let file = f.folder.appendingPathComponent("letterbox.png")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(padded.tiffRepresentation)))
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:])); try data.write(to: file)
        var record = LibraryRecord(id: UUID(), kind: .link, createdAt: f.date, updatedAt: f.date)
        record.originalURL = "https://youtu.be/jNQXAC9IVRw"; record.thumbnailPath = file.path
        let preview = LinkPreview(record: record); defer { preview.window.close() }
        wait { preview.hasThumbnail }
        func findImage(_ view: NSView) -> NSImageView? { if let v = view as? NSImageView { return v }; return view.subviews.lazy.compactMap { findImage($0) }.first }
        let view = try XCTUnwrap(preview.window.contentView.flatMap { findImage($0) })
        XCTAssertEqual(view.image?.size, NSSize(width: 480, height: 270))
        record = LibraryRecord(id: UUID(), kind: .link, createdAt: f.date, updatedAt: f.date)
        record.originalURL = "https://example.com/preserve"; record.thumbnailPath = file.path; preview.replace(record); wait { preview.hasThumbnail }
        XCTAssertEqual(view.image?.size, NSSize(width: 480, height: 360)); XCTAssertEqual(try Data(contentsOf: file), data)
    }
    private func shelfIDs(_ line: Line, _ shelf: Shelf) -> [UUID] {
        switch shelf { case .images: line.displayItems.filter { !$0.falling }.map(\.id); case .texts: line.texts.displayEntries.map(\.id); case .links: line.links.displayEntries.map(\.id) }
    }
    private func shelfSelection(_ line: Line, _ shelf: Shelf) -> Set<UUID> {
        switch shelf { case .images: line.selectedIDs; case .texts: line.texts.selectedIDs; case .links: line.links.selectedIDs }
    }
    private func shelfFocus(_ line: Line, _ shelf: Shelf) -> UUID? {
        switch shelf { case .images: line.focusedID; case .texts: line.texts.focusedID; case .links: line.links.focusedID }
    }
    private func shelfOffset(_ line: Line, _ shelf: Shelf) -> CGFloat {
        switch shelf { case .images: line.scrollOffset; case .texts: line.texts.scrollOffset; case .links: line.links.scrollOffset }
    }
    private func populateShelves(_ f: SyntheticFixture, _ store: LibraryStore, count: Int) throws {
        for index in 0..<count {
            _ = try store.captureImage(f.image())
            _ = try store.captureText("opening selection text \(index)")
            _ = try store.captureLink(try XCTUnwrap(URL(string: "https://example.com/opening/\(index)")))
            f.date.addTimeInterval(1)
        }
    }
    func testClosingClearsEverySelectionAndReopeningSelectsFirstVisibleItemsAndPage() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populateShelves(f, store, count: 12)
        let line = Line(defaults: f.defaults, inbox: f.inbox, breeze: false, library: store)
        line.setPresentation(.all, requestFocus: false); line.setViewportWidth(720)
        var focusRequests = 0; line.onFocusRequested = { focusRequests += 1 }
        line.revealed = true
        for shelf in Shelf.allCases {
            XCTAssertEqual(shelfSelection(line, shelf), shelf == .images ? [try XCTUnwrap(shelfIDs(line, shelf).first)] : [])
            line.focusShelf(shelf, requestFocus: false)
            XCTAssertNotNil(line.moveShelfPage(1)); XCTAssertTrue(shelfOffset(line, shelf) > 0)
            line.selectAllActive()
        }
        line.focusShelf(.texts, requestFocus: false)
        line.revealed = false
        for shelf in Shelf.allCases { XCTAssertTrue(shelfSelection(line, shelf).isEmpty); XCTAssertNil(shelfFocus(line, shelf)) }
        // A preview can still browse while the shelf is hidden. Its selection
        // must not leak into the next shelf session either.
        line.selectAll(); line.texts.selectAll(); line.links.selectAll()
        line.revealed = true
        XCTAssertEqual(line.activeShelf, .images); XCTAssertEqual(line.presentation, .all)
        for shelf in Shelf.allCases {
            let first = try XCTUnwrap(shelfIDs(line, shelf).first)
            XCTAssertEqual(shelfSelection(line, shelf), shelf == .images ? [first] : [])
            XCTAssertEqual(shelfFocus(line, shelf), shelf == .images ? first : nil)
            XCTAssertEqual(shelfOffset(line, shelf), 0)
            line.focusShelf(shelf, requestFocus: false)
            XCTAssertEqual(line.quickSelectionIDs.first, first, "Reopening discards the previous numbered page")
        }
        XCTAssertEqual(focusRequests, 0, "Automatic reveals select content without requesting keyboard focus")
    }
    func testSingleShelfOpeningLeavesHiddenRowsEmptyAndRepeatedRevealPreservesBatch() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populateShelves(f, store, count: 3)
        let line = Line(defaults: f.defaults, inbox: f.inbox, breeze: false, library: store)
        for shelf in Shelf.allCases {
            line.revealed = false
            line.setPresentation(shelf.presentation, requestFocus: false)
            // Stale preview focus can exist even in rows hidden by presentation.
            line.selectAll(); line.texts.selectAll(); line.links.selectAll()
            line.revealed = true
            XCTAssertEqual(line.activeShelf, shelf)
            for row in Shelf.allCases {
                if row == shelf {
                    XCTAssertEqual(shelfSelection(line, row), [try XCTUnwrap(shelfIDs(line, row).first)])
                } else {
                    XCTAssertTrue(shelfSelection(line, row).isEmpty); XCTAssertNil(shelfFocus(line, row))
                }
            }
            line.selectAllActive()
            let batch = line.activeIDs, focus = shelfFocus(line, shelf)
            line.revealed = true
            XCTAssertEqual(line.activeIDs, batch); XCTAssertEqual(shelfFocus(line, shelf), focus)
            XCTAssertEqual(batch.count, 3, "A redundant reveal must not replace an in-progress batch")
        }
    }
    func testOpeningSelectsFirstPinnedItemAndLeavesEmptyFilteredShelvesUnselected() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        let image = try store.captureImage(f.image()), text = try XCTUnwrap(store.captureText("saved opening note"))
        try store.toggleFavorite([image.id, text.id]); f.date.addTimeInterval(1)
        try populateShelves(f, store, count: 2)
        let line = Line(defaults: f.defaults, inbox: f.inbox, breeze: false, library: store)
        line.setPresentation(.all, requestFocus: false)
        line.setFavoritesOnly(true); line.texts.setFavoritesOnly(true); line.links.setFavoritesOnly(true)
        line.focusShelf(.links, requestFocus: false); line.revealed = true
        XCTAssertEqual(line.selectedIDs, [image.id]); XCTAssertTrue(line.texts.selectedIDs.isEmpty)
        XCTAssertTrue(line.links.selectedIDs.isEmpty); XCTAssertNil(line.links.focusedID)
        XCTAssertEqual(line.activeShelf, .images, "A fresh reveal prefers the first available image")
        XCTAssertTrue(line.favoritesOnly); XCTAssertTrue(line.texts.favoritesOnly); XCTAssertTrue(line.links.favoritesOnly)
        line.revealed = false; line.revealed = true
        XCTAssertEqual(line.selectedIDs, [image.id]); XCTAssertTrue(line.texts.selectedIDs.isEmpty)
        XCTAssertTrue(line.links.selectedIDs.isEmpty)
    }
    func testEnablingShelfSelectsItsFirstItemWithoutResettingAlreadyVisibleRows() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        try populateShelves(f, store, count: 8)
        let line = Line(defaults: f.defaults, inbox: f.inbox, breeze: false, library: store)
        line.setPresentation(.images, requestFocus: false); line.setViewportWidth(720); line.revealed = true
        line.moveToShelfBoundary(last: true)
        let imageSelection = line.selectedIDs, imageFocus = line.focusedID, imageOffset = line.scrollOffset
        line.texts.select(try XCTUnwrap(line.texts.displayEntries.last).id, width: line.viewportWidth)
        line.links.select(try XCTUnwrap(line.links.displayEntries.last).id, width: line.viewportWidth)
        var focusRequests = 0; line.onFocusRequested = { focusRequests += 1 }
        line.setPresentation(.both, requestFocus: false)
        XCTAssertTrue(line.texts.selectedIDs.isEmpty); XCTAssertNil(line.texts.focusedID)
        XCTAssertEqual(line.texts.scrollOffset, 0)
        XCTAssertEqual(line.selectedIDs, imageSelection); XCTAssertEqual(line.focusedID, imageFocus); XCTAssertEqual(line.scrollOffset, imageOffset)
        let textFocus = line.texts.focusedID
        line.setPresentation(.all, requestFocus: false)
        XCTAssertTrue(line.links.selectedIDs.isEmpty); XCTAssertNil(line.links.focusedID); XCTAssertEqual(line.links.scrollOffset, 0)
        XCTAssertEqual(line.texts.focusedID, textFocus)
        XCTAssertEqual(line.selectedIDs, imageSelection); XCTAssertEqual(line.scrollOffset, imageOffset)
        XCTAssertEqual(line.activeShelf, .images); XCTAssertEqual(focusRequests, 0)
    }
    func testSRemovesOnlySelectedShelfItemsAndKeepsSavedRecordsRecoverable() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let image = try store.captureImage(try f.image()), other = try store.captureImage(try f.image())
        let text = try XCTUnwrap(store.captureText("saved text")), temporary = try XCTUnwrap(store.captureText("temporary text"))
        let link = try store.captureLink(URL(string: "https://example.com/selected")!)
        try store.toggleFavorite([image.id, text.id, link.id])
        let line = Line(defaults: f.defaults, inbox: f.inbox, breeze: false, library: store)
        let keyboard = LineKeyboard(line: line, onCopy: { _ in }, onPreview: { _ in }, onClose: {})
        XCTAssertTrue(keyboard.handle(key(1, [], "s"))); XCTAssertTrue(try store.item(image.id)?.onShelf == true)
        line.select(image.id); XCTAssertTrue(keyboard.handle(key(1, [], "s")))
        XCTAssertFalse(try store.item(image.id)?.onShelf == true); XCTAssertNil(try store.item(image.id)?.deletedAt)
        XCTAssertTrue(try store.item(other.id)?.onShelf == true)
        line.focusShelf(.texts, requestFocus: false); line.texts.select(text.id, width: line.viewportWidth); line.texts.select(temporary.id, toggle: true, width: line.viewportWidth)
        XCTAssertTrue(keyboard.handle(key(1, [], "s")))
        XCTAssertFalse(try store.item(text.id)?.onShelf == true); XCTAssertNil(try store.item(text.id)?.deletedAt)
        XCTAssertTrue(try store.item(temporary.id)?.deletedAt != nil)
        try store.restore([temporary.id]); XCTAssertNil(try store.item(temporary.id)?.deletedAt)
        line.focusShelf(.links, requestFocus: false); line.links.select(link.id, width: line.viewportWidth)
        XCTAssertTrue(keyboard.handle(key(1, [], "s"))); XCTAssertFalse(try store.item(link.id)?.onShelf == true)
        XCTAssertNil(try store.item(link.id)?.deletedAt)
        for context in [KeyboardContext.imagePreview, .textPreview, .linkPreview] {
            XCTAssertEqual(line.keyboardBindings.action(for: key(1, [], "s"), in: context), .removeFromLine)
            XCTAssertEqual(line.keyboardBindings.action(for: key(51), in: context), .undoRemoveFromLine)
        }
        XCTAssertEqual(line.keyboardBindings.action(for: key(1, [], "s"), in: .library), .trash)
        try line.keyboardBindings.set([KeyShortcut(keyCode: 2, modifiers: 0, keyLabel: "D")], for: .removeFromLine)
        XCTAssertFalse(keyboard.handle(key(1, [], "s")))
        XCTAssertEqual(KeyboardBindings(defaults: f.defaults).action(for: key(2, [], "d"), in: .line), .removeFromLine)
        for context in [KeyboardContext.imagePreview, .textPreview, .linkPreview] {
            XCTAssertNil(line.keyboardBindings.action(for: key(1, [], "s"), in: context))
            XCTAssertEqual(KeyboardBindings(defaults: f.defaults).action(for: key(2, [], "d"), in: context), .removeFromLine)
        }
    }
    func testShortcutRecorderCapturesPlainAndCommandKeysAndSavesChosenValue() throws {
        _ = NSApplication.shared
        let recorder = ShortcutRecorder(allowPlain: true)
        var captured: KeyShortcut?, callbacks = 0
        recorder.onFinish = { captured = $0; callbacks += 1 }
        recorder.window.sendEvent(key(40, [], "k"))
        let save = try XCTUnwrap(recorder.window.contentView?.subviews.compactMap { $0 as? NSButton }.first { $0.title == L("Save shortcut") })
        XCTAssertTrue(save.isEnabled)
        recorder.window.sendEvent(key(2, .command, "d"))
        save.performClick(nil)
        XCTAssertEqual(captured, KeyShortcut(keyCode: 2, modifiers: cmdKey, keyLabel: "D")); XCTAssertEqual(callbacks, 1)
    }
    func testSingleKeysOpenLibraryPinFilterAndPersistRemappingAcrossContexts() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        let line = Line(defaults: f.defaults, inbox: f.inbox, breeze: false, library: store)
        let id = try XCTUnwrap(line.hang(try f.image(), quietly: true)); line.select(id)
        var libraries = 0; line.onLibraryRequested = { libraries += 1 }
        let keyboard = LineKeyboard(line: line, onCopy: { _ in }, onPreview: { _ in }, onClose: {})
        XCTAssertTrue(keyboard.handle(key(37, [], "l"))); XCTAssertEqual(libraries, 1)
        XCTAssertTrue(keyboard.handle(key(35, [], "p"))); XCTAssertTrue(try store.item(id)?.favorite == true)
        XCTAssertTrue(keyboard.handle(key(3, [], "f"))); XCTAssertTrue(line.favoritesOnly)
        XCTAssertTrue(keyboard.handle(key(3, [], "f"))); XCTAssertFalse(line.favoritesOnly)
        let other = KeyboardBindings(defaults: f.defaults)
        try line.keyboardBindings.set([KeyShortcut(keyCode: 40, modifiers: 0, keyLabel: "K")], for: .pin)
        XCTAssertEqual(other.action(for: key(40, [], "k"), in: .library), .pin)
        XCTAssertEqual(other.action(for: key(40, [], "k"), in: .imagePreview), .pin)
        XCTAssertFalse(keyboard.handle(key(35, [], "p")))
        line.select(id); XCTAssertTrue(keyboard.handle(key(40, [], "k"))); XCTAssertFalse(try store.item(id)?.favorite == true)
        let model = LibraryModel(store: store)
        XCTAssertFalse(model.handleKey(key(40, [], "k"), editing: true))
        model.changeScope(.favorites); wait { !model.loading }
        XCTAssertTrue(model.showingPinnedOnly)
        XCTAssertTrue(model.handleKey(key(3, [], "f"), editing: false)); wait { !model.loading }
        XCTAssertEqual(model.query.scope, .saved); XCTAssertFalse(model.showingPinnedOnly)
        XCTAssertNil(KeyShortcut.capture(key(40, [], "k")))
        XCTAssertEqual(KeyShortcut.capture(key(40, [], "k"), allowPlain: true)?.keyCode, 40)
    }
    func testShortcutConflictsAndResetAreRejectedWithoutChangingExistingBindings() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }; let keys = KeyboardBindings(defaults: f.defaults)
        var rejected = false
        do { try keys.set([KeyShortcut(keyCode: 35, modifiers: 0, keyLabel: "P")], for: .copy) } catch { rejected = true }
        XCTAssertTrue(rejected); XCTAssertEqual(keys.shortcuts(.copy), KeyboardAction.copy.defaults)
        try keys.set([], for: .pin)
        try keys.set([KeyShortcut(keyCode: 35, modifiers: 0, keyLabel: "P")], for: .library)
        rejected = false; do { try keys.reset(.pin) } catch { rejected = true }
        XCTAssertTrue(rejected); XCTAssertTrue(keys.shortcuts(.pin).isEmpty)
        XCTAssertEqual(keys.action(for: key(35, [], "p"), in: .line), .library)
        try keys.reset(); XCTAssertEqual(keys.action(for: key(35, [], "p"), in: .line), .pin)
        XCTAssertEqual(keys.action(for: key(36, .command), in: .textPreview), .paste)
        XCTAssertEqual(keys.action(for: key(36, .command), in: .linkPreview), .paste)
    }
    func testIndependentRetentionKeepsOtherKindsAndPermanentItemsAndSurvivesReopen() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        let image = try store.captureImage(try f.image()), text = try XCTUnwrap(store.captureText("temporary text"))
        let link = try store.captureLink(URL(string: "https://example.com/temporary")!), saved = try XCTUnwrap(store.captureText("permanent text"))
        try store.toggleFavorite([saved.id])
        f.date.addTimeInterval(4 * 86400)
        let line = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false, library: store)
        line.setRetentionDays(3, for: .text)
        XCTAssertTrue(try store.item(text.id)?.deletedAt != nil)
        XCTAssertNil(try store.item(image.id)?.deletedAt); XCTAssertNil(try store.item(link.id)?.deletedAt); XCTAssertNil(try store.item(saved.id)?.deletedAt)
        line.setRetentionDays(1, for: .image)
        XCTAssertEqual(line.retentionDays(for: .text), 3); XCTAssertEqual(line.retentionDays(for: .link), 30)
        XCTAssertTrue(try store.item(image.id)?.deletedAt != nil); XCTAssertNil(try store.item(link.id)?.deletedAt)
        line.setRetentionDays(3, for: .link); XCTAssertTrue(try store.item(link.id)?.deletedAt != nil)
        let reopened = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        XCTAssertEqual(reopened.retentionDays(for: .image), 1); XCTAssertEqual(reopened.retentionDays(for: .text), 3); XCTAssertEqual(reopened.retentionDays(for: .link), 3)
        XCTAssertNil(try reopened.item(saved.id)?.deletedAt); XCTAssertTrue(try reopened.item(saved.id)?.favorite == true)
    }
    func testFinishingTextEditSavesBeforeBrowsingAndFailedSaveKeepsEditableDraft() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let preview = TextPreview(text: "original", keyboardBindings: KeyboardBindings(defaults: f.defaults)); defer { preview.window.close() }
        var saved = "", moved = 0
        preview.onSave = { saved = $0; return true }; preview.onKey = { _ in moved += 1; return true }
        preview.beginEditing(); preview.textView.string = "Edited İstanbul 🌍"; preview.textDidChange(Notification(name: NSText.didChangeNotification))
        XCTAssertFalse(preview.routeKey(key(124))); XCTAssertEqual(moved, 0)
        XCTAssertTrue(preview.routeKey(key(36, .command))); XCTAssertFalse(preview.isEditing); XCTAssertEqual(saved, "Edited İstanbul 🌍")
        XCTAssertTrue(preview.routeKey(key(124))); XCTAssertEqual(moved, 1)
        preview.beginEditing(); preview.textView.string = "failed draft"; preview.textDidChange(Notification(name: NSText.didChangeNotification)); preview.onSave = { _ in false }
        XCTAssertTrue(preview.routeKey(key(53))); XCTAssertTrue(preview.isEditing); XCTAssertEqual(preview.textView.string, "failed draft")
        preview.onSave = { _ in true }; XCTAssertTrue(preview.finishEditing())
    }
    func testLinkPreviewFitsThumbnailAndOpensExactCurrentURLWithConfiguredKey() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let keys = KeyboardBindings(defaults: f.defaults)
        var record = LibraryRecord(id: UUID(), kind: .link, createdAt: f.date, updatedAt: f.date)
        record.originalURL = "https://youtu.be/jNQXAC9IVRw?t=20"; record.thumbnailPath = try f.image().path; record.title = String(repeating: "A long video title ", count: 12)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 750, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: record.thumbnailPath!))
        let preview = LinkPreview(record: record, keyboardBindings: keys); defer { preview.window.close() }
        preview.window.contentView?.layoutSubtreeIfNeeded(); wait { preview.hasThumbnail }
        func imageView(_ view: NSView) -> NSImageView? { if let image = view as? NSImageView, image.accessibilityLabel() == L("Link thumbnail") { return image }; return view.subviews.lazy.compactMap { imageView($0) }.first }
        let image = try XCTUnwrap(preview.window.contentView.flatMap { imageView($0) })
        preview.window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertTrue(preview.window.frame.width <= 660)
        XCTAssertEqual(image.imageScaling, .scaleProportionallyUpOrDown)
        XCTAssertTrue(image.frame.width > 0); XCTAssertTrue(abs(image.frame.height / max(1, image.frame.width) - 9.0 / 16.0) < 0.02)
        let surface = try XCTUnwrap(preview.window.contentView)
        let imageRect = surface.convert(image.bounds, from: image)
        XCTAssertTrue(abs(imageRect.maxY - (preview.controls.frame.minY - 14)) < 2, "Thumbnail must start below the controls without a centered document gap")
        var opened: URL?; preview.onOpen = { opened = $0 }
        XCTAssertTrue(preview.window.onKey?(key(31, .command, "o")) ?? false); XCTAssertEqual(opened?.absoluteString, record.originalURL)
        try keys.set([KeyShortcut(keyCode: 38, modifiers: cmdKey, keyLabel: "J")], for: .open)
        record.originalURL = "https://example.com/next"; record.thumbnailPath = nil; preview.replace(record)
        XCTAssertFalse(preview.hasThumbnail)
        XCTAssertTrue(preview.window.onKey?(key(38, .command, "j")) ?? false); XCTAssertEqual(opened?.absoluteString, record.originalURL)
    }
    func testEditingSearchResultKeepsDraftUntilDoneAndArrowsUseRemainingResults() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        for body in ["marker first", "marker second"] { let record = try XCTUnwrap(store.captureText(body)); try store.retain([record.id]) }
        let model = LibraryModel(store: store); model.search = "marker"; wait { model.ids.count == 2 }
        let first = model.ids[0], second = model.ids[1]
        let controller = LibraryPreviewController(model: model); defer { controller.close() }
        controller.show(first)
        let preview = try XCTUnwrap(controller.text)
        preview.beginEditing(); preview.textView.string = "changed İstanbul 🌍"; preview.textDidChange(Notification(name: NSText.didChangeNotification))
        XCTAssertTrue(preview.flushEdits()); wait { model.ids == [second] }
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        XCTAssertEqual(controller.currentID, first); XCTAssertTrue(preview.isEditing)
        XCTAssertEqual(preview.textView.string, "changed İstanbul 🌍")
        XCTAssertTrue(preview.routeKey(key(36, .command))); XCTAssertFalse(preview.isEditing)
        XCTAssertTrue(preview.routeKey(key(124))); XCTAssertEqual(controller.currentID, second)
        XCTAssertEqual(controller.text?.textView.string, try store.item(second)?.text)
        XCTAssertEqual(try store.item(first)?.text, "changed İstanbul 🌍")
    }
}
