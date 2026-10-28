import AppKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class PreviewInteractionTests: HistoryTestCase {
    private func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [], text: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
    }
    func testTextEditsPreserveIdentityDatePinOrderAndExportedCopy() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let texts = f.texts(); texts.add("first note"); let before = texts.entries[0]
        texts.togglePin(before.id); texts.add("second note")
        let file = try texts.materialize(try XCTUnwrap(texts.entries.first { $0.id == before.id }))
        let edited = "İstanbul 👋\n中文\nEdited note"
        XCTAssertTrue(texts.updateText(before.id, to: edited))
        let after = try XCTUnwrap(texts.entries.first { $0.id == before.id })
        XCTAssertEqual(after.capturedAt, before.capturedAt); XCTAssertTrue(after.pinned)
        XCTAssertEqual(texts.entries.last?.id, before.id)
        XCTAssertEqual(f.texts().entries, texts.entries)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), edited)
        XCTAssertEqual(try texts.materialize(after), file)
        XCTAssertTrue(texts.updateText(before.id, to: ""))
        XCTAssertEqual(texts.entries.last?.text, "")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "")
    }
    func testEditingRejectsCorruptArchiveAndSymlinkWithoutChangingData() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let texts = f.texts(); texts.add("original note"); let id = texts.entries[0].id
        let target = f.folder.appendingPathComponent("outside.txt"); try Data("outside".utf8).write(to: target)
        let materialized = texts.folder.appendingPathComponent("Text \(id).txt")
        try FileManager.default.createSymbolicLink(at: materialized, withDestinationURL: target)
        XCTAssertFalse(texts.updateText(id, to: "edited"))
        XCTAssertEqual(f.texts().entries[0].text, "original note")
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "outside")
        let corrupt = Data("invalid archive".utf8); try corrupt.write(to: texts.archive)
        XCTAssertFalse(f.texts().updateText(id, to: "edited"))
        XCTAssertEqual(try Data(contentsOf: texts.archive), corrupt)
    }
    func testTextCopyFeedbackCoversSingleAndBatchCopies() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        var copied: [String] = []
        let texts = TextHistory(defaults: f.defaults, folder: f.inbox.appendingPathComponent("Texts"), copyText: { copied.append($0) })
        texts.add("one"); texts.add("two"); let id = texts.entries[0].id
        texts.copy(id); XCTAssertEqual(texts.copiedIDs, [id]); XCTAssertEqual(copied, ["two"])
        texts.selectAll(); texts.copySelection()
        XCTAssertEqual(texts.copiedIDs, Set(texts.entries.map(\.id)))
        XCTAssertEqual(copied.last, "two\n\none")
    }
    func testPinAndFavoritesShortcutsAreSymmetricAcrossShelves() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let line = f.line(); line.hang(try f.image(), quietly: true); line.texts.add("note")
        let keyboard = LineKeyboard(line: line, onCopy: { _ in }, onPreview: { _ in }, onClose: {})
        line.selectAll(); XCTAssertTrue(keyboard.handle(key(35, flags: .command, text: "p")))
        XCTAssertTrue(line.items[0].pinned)
        XCTAssertTrue(keyboard.handle(key(3, flags: [.command, .shift], text: "f")))
        XCTAssertTrue(line.favoritesOnly); XCTAssertFalse(line.texts.favoritesOnly)
        line.focusShelf(.texts, requestFocus: false); line.texts.selectAll()
        XCTAssertTrue(keyboard.handle(key(35, flags: .command, text: "p")))
        XCTAssertTrue(line.texts.entries[0].pinned)
        XCTAssertTrue(keyboard.handle(key(3, flags: [.command, .shift], text: "f")))
        XCTAssertTrue(line.texts.favoritesOnly)
        XCTAssertTrue(keyboard.handle(key(3, flags: [.command, .shift], text: "f")))
        XCTAssertFalse(line.texts.favoritesOnly); XCTAssertTrue(line.favoritesOnly)
    }
    func testImagePreviewNavigationCopiesOnlyCurrentItemAndClampsAtEnds() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        var copied: [URL] = []
        let line = Line(defaults: f.defaults, inbox: f.inbox, breeze: false, moveToTrash: fixtureTrash(f.folder), copyImage: { copied.append($0) })
        for _ in 0..<3 { line.hang(try f.image(), quietly: true) }
        line.selectAll()
        let session = ShelfPreviewSession(line: line, shelf: .images, id: line.items[0].id)
        XCTAssertTrue(session.move(1)); XCTAssertEqual(session.currentID, line.items[1].id)
        session.copy(); XCTAssertEqual(copied, [line.items[1].url])
        XCTAssertTrue(session.move(50)); XCTAssertEqual(session.currentID, line.items[2].id)
        XCTAssertTrue(session.move(-50)); XCTAssertEqual(session.currentID, line.items[0].id)
        XCTAssertTrue(session.togglePin()); XCTAssertTrue(session.pinned)
    }
    func testTextPreviewNavigationSavesAndCopiesCurrentEditedNote() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        var copied: [String] = []
        let line = Line(defaults: f.defaults, inbox: f.inbox, breeze: false, copyText: { copied.append($0) })
        line.texts.add("first"); line.texts.add("second"); line.texts.selectAll()
        let session = ShelfPreviewSession(line: line, shelf: .texts, id: line.texts.entries[0].id)
        XCTAssertTrue(session.move(1)); XCTAssertTrue(session.saveText("edited first")); session.copy()
        XCTAssertEqual(copied, ["edited first"]); XCTAssertEqual(session.text, "edited first")
        XCTAssertTrue(session.togglePin()); XCTAssertTrue(session.pinned)
    }
    func testUnpinningInFilteredPreviewMovesToNeighborOrReportsEmpty() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let line = f.line(); line.texts.add("one"); line.texts.add("two")
        for entry in line.texts.entries { line.texts.togglePin(entry.id) }
        line.texts.setFavoritesOnly(true)
        let last = line.texts.entries[1].id
        let session = ShelfPreviewSession(line: line, shelf: .texts, id: line.texts.entries[0].id)
        XCTAssertTrue(session.togglePin()); XCTAssertEqual(session.currentID, last)
        XCTAssertFalse(session.togglePin()); XCTAssertTrue(line.texts.displayEntries.isEmpty)
    }
    func testBorderlessTextPreviewSeparatesBrowsingAndEditingKeysAndFlushesEdits() throws {
        _ = NSApplication.shared
        let preview = TextPreview(text: "original")
        defer { preview.window.close() }
        XCTAssertFalse(preview.window.styleMask.contains(.titled)); XCTAssertTrue(preview.window.canBecomeKey)
        XCTAssertFalse(preview.textView.isEditable)
        var keys = 0; var saved = ""
        preview.onKey = { _ in keys += 1; return true }; preview.onSave = { saved = $0; return true }
        XCTAssertTrue(preview.routeKey(key(124))); XCTAssertEqual(keys, 1)
        preview.beginEditing(); XCTAssertTrue(preview.textView.isEditable)
        XCTAssertFalse(preview.routeKey(key(124))); XCTAssertFalse(preview.routeKey(key(49)))
        XCTAssertFalse(preview.routeKey(key(8, flags: .command, text: "c")))
        XCTAssertTrue(preview.routeKey(key(35, flags: .command, text: "p")))
        preview.textView.string = "updated 👋"; preview.textDidChange(Notification(name: NSText.didChangeNotification))
        XCTAssertTrue(preview.flushEdits()); XCTAssertEqual(saved, "updated 👋")
        preview.replaceText("neighbor"); XCTAssertFalse(preview.isEditing); XCTAssertFalse(preview.textView.isEditable)
        XCTAssertTrue(preview.routeKey(key(124)))
    }
    func testFailedTextSaveKeepsDraftForCorrection() throws {
        _ = NSApplication.shared
        let preview = TextPreview(text: "original"); defer { preview.window.close() }
        preview.onSave = { _ in false }; preview.beginEditing()
        preview.textView.string = "draft"; preview.textDidChange(Notification(name: NSText.didChangeNotification))
        XCTAssertFalse(preview.flushEdits()); XCTAssertEqual(preview.textView.string, "draft")
        XCTAssertTrue(preview.isEditing)
    }
    func testEditingMenuSelectsAndCopiesUnicodePreviewTextToPrivateClipboard() throws {
        _ = NSApplication.shared
        let board = NSPasteboard(name: NSPasteboard.Name("local.clipboardline.editing-test.\(UUID())"))
        defer { board.releaseGlobally() }
        let value = "İstanbul 👋\n中文\nA note"
        let preview = TextPreview(text: value, copyPasteboard: board)
        defer { preview.window.close() }
        preview.beginEditing()
        let menu = EditingMenu.makeMenu()
        let select = try XCTUnwrap(menu.items.firstIndex { $0.action == NSSelectorFromString("selectAll:") })
        let copy = try XCTUnwrap(menu.items.firstIndex { $0.action == NSSelectorFromString("copy:") })
        menu.items[select].target = preview.textView; menu.items[copy].target = preview.textView
        menu.performActionForItem(at: select)
        XCTAssertEqual(preview.textView.selectedRange(), NSRange(location: 0, length: (value as NSString).length))
        menu.performActionForItem(at: copy)
        XCTAssertEqual(board.string(forType: .string), value)
        preview.textView.setSelectedRange((value as NSString).range(of: "中文"))
        menu.performActionForItem(at: copy)
        XCTAssertEqual(board.string(forType: .string), "中文")
        XCTAssertEqual(preview.textView.string, value)
    }
    func testFastScrollDiscardsIntermediateWorkAndLoadsLatestRangeOffMainThread() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let line = f.line(); line.setViewportWidth(400)
        for _ in 0..<110 { line.hang(try f.image(), quietly: true) }
        let before = line.thumbnails.decodeCount
        for i in 0..<120 { line.setScrollOffset(CGFloat((i * 11) % 110) * Layout.spacing) }
        line.setScrollOffset(line.maximumScrollOffset)
        let deadline = Date().addingTimeInterval(3)
        while line.thumbnails.pendingCount > 0 && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertEqual(line.thumbnails.pendingCount, 0)
        XCTAssertFalse(line.thumbnails.decodedOnMainThread)
        XCTAssertTrue(line.thumbnails.peakConcurrentDecodes <= 2)
        XCTAssertTrue(line.thumbnails.decodeCount - before <= line.visibleRange.count + 2)
        XCTAssertTrue(line.items.last?.thumb != nil); XCTAssertNil(line.items.first?.thumb)
        XCTAssertTrue(line.items.filter { $0.thumb != nil }.count <= line.visibleRange.count)
        let decoded = line.thumbnails.decodeCount
        line.setScrollOffset(line.maximumScrollOffset - 1); line.setScrollOffset(line.maximumScrollOffset)
        XCTAssertEqual(line.thumbnails.decodeCount, decoded)
    }
    func testRecycledCardsDoNotReplayArrivalAnimations() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let line = f.line(); let id = try XCTUnwrap(line.hang(try f.image(), quietly: true))
        XCTAssertTrue(line.consumeArrival(id)); XCTAssertFalse(line.consumeArrival(id))
    }
    func testThumbnailBudgetDoesNotContinuouslyDecodeAnOversizedRange() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 512,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.bitmapData?.initialize(repeating: 0, count: rep.bytesPerRow * rep.pixelsHigh)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let urls = try (0..<40).map { _ in let url = try f.image(); try data.write(to: url); return url }
        let thumbnails = ThumbnailStore(); thumbnails.request(urls, pixels: 512)
        let deadline = Date().addingTimeInterval(4)
        while thumbnails.pendingCount > 0 && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertEqual(thumbnails.pendingCount, 0); XCTAssertTrue(thumbnails.decodeCount <= 32)
        XCTAssertTrue(thumbnails.cachedCount <= 64); XCTAssertTrue(thumbnails.cachedBytes <= ThumbnailStore.maximumBytes)
        let decoded = thumbnails.decodeCount
        thumbnails.request(urls, pixels: 512); RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(thumbnails.decodeCount, decoded)
        thumbnails.request(Array(urls.suffix(4)), pixels: 512)
        let latestDeadline = Date().addingTimeInterval(2)
        while thumbnails.pendingCount > 0 && Date() < latestDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(urls.suffix(4).allSatisfy { thumbnails.image(for: $0, pixels: 512) != nil })
        XCTAssertTrue(thumbnails.peakConcurrentDecodes <= 2); XCTAssertFalse(thumbnails.decodedOnMainThread)
    }
}
