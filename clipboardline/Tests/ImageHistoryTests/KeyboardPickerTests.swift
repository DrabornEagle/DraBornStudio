import AppKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class KeyboardPickerTests: HistoryTestCase {
    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = [], _ text: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
    }
    func testFolderSearchMatchesFoldedParentPathsAndNeverPinsHiddenChoice() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let note = try XCTUnwrap(store.captureText("filtered folder"))
        let parent = try store.createCollection("İçerik Fikirleri")
        let child = try store.createCollection("Çekimler", parent: parent)
        _ = try store.createCollection("Unrelated")
        let light = try store.createCollection("IŞIK Planı")
        let picker = try PinFolderPicker(store: store, ids: [note.id]); defer { picker.window.close() }
        picker.setSearchQuery("ışık planı"); XCTAssertEqual(picker.choices.map(\.id), [light])
        picker.setSearchQuery("ISIK PLANI"); XCTAssertEqual(picker.choices.map(\.id), [light])
        picker.setSearchQuery("icerik cekim")
        XCTAssertEqual(picker.choices.map(\.id), [child]); XCTAssertEqual(picker.table.selectedRow, 0)
        XCTAssertFalse(picker.handle(key(125, .shift))); XCTAssertFalse(picker.handle(key(126, .shift)))
        XCTAssertEqual(picker.table.selectedRow, 0)
        picker.setSearchQuery("no such folder")
        XCTAssertTrue(picker.choices.isEmpty); XCTAssertTrue(picker.handle(key(36)))
        XCTAssertFalse(try store.item(note.id)?.favorite == true)
        picker.setSearchQuery("cek")
        XCTAssertTrue(picker.handle(key(125))); XCTAssertEqual(picker.table.selectedRow, 0)
        XCTAssertTrue(picker.handle(key(36)))
        XCTAssertEqual(try store.collections(for: note.id).map(\.id), [child])
        XCTAssertTrue(try store.item(note.id)?.favorite == true)
    }
    func testFolderRecentsAreIsolatedPersistentBoundedAndRecordedOnlyAfterSuccess() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let note = try XCTUnwrap(store.captureText("recent folder"))
        let first = try store.createCollection("A folder"), recent = try store.createCollection("Z folder")
        let picker = try PinFolderPicker(store: store, ids: [note.id]); defer { picker.window.close() }
        XCTAssertEqual(picker.choices.first?.id, first)
        picker.setSearchQuery("Z folder"); XCTAssertTrue(picker.handle(key(36)))
        XCTAssertEqual(f.defaults.stringArray(forKey: PinFolderPicker.recentFoldersKey), [recent.uuidString])
        let next = try PinFolderPicker(store: store, ids: [note.id]); defer { next.window.close() }
        XCTAssertEqual(next.choices.first?.id, recent)
        next.setSearchQuery("A folder"); XCTAssertTrue(next.handle(key(53)))
        XCTAssertEqual(f.defaults.stringArray(forKey: PinFolderPicker.recentFoldersKey), [recent.uuidString])
        let invalid = try PinFolderPicker(store: store, ids: [note.id, UUID()]); defer { invalid.window.close() }
        invalid.setSearchQuery("A folder"); XCTAssertTrue(invalid.handle(key(36)))
        XCTAssertEqual(f.defaults.stringArray(forKey: PinFolderPicker.recentFoldersKey), [recent.uuidString])
        XCTAssertEqual(try store.collections(for: note.id).map(\.id), [recent])
        f.defaults.set(Array((0..<12).map { _ in UUID().uuidString }), forKey: PinFolderPicker.recentFoldersKey)
        let bounded = try PinFolderPicker(store: store, ids: [note.id]); defer { bounded.window.close() }
        bounded.setSearchQuery("A folder"); XCTAssertTrue(bounded.handle(key(36)))
        XCTAssertEqual(f.defaults.stringArray(forKey: PinFolderPicker.recentFoldersKey)?.count, 8)
        XCTAssertEqual(f.defaults.stringArray(forKey: PinFolderPicker.recentFoldersKey)?.first, first.uuidString)
    }
    func testFolderKeyboardCreationCanCancelAndKeepsNativeEditingKeys() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let note = try XCTUnwrap(store.captureText("new folder keyboard"))
        let picker = try PinFolderPicker(store: store, ids: [note.id]); defer { picker.window.close() }
        picker.setSearchQuery("Ideas")
        XCTAssertTrue(picker.handle(key(45, .command, "n"))); XCTAssertTrue(picker.creating)
        XCTAssertFalse(picker.handle(key(123))); XCTAssertFalse(picker.handle(key(124)))
        XCTAssertFalse(picker.handle(key(125, .shift))); XCTAssertFalse(picker.handle(key(126, .shift)))
        XCTAssertFalse(picker.handle(key(1, [], "s"))); XCTAssertFalse(picker.handle(key(51)))
        XCTAssertTrue(picker.handle(key(53))); XCTAssertFalse(picker.creating)
        XCTAssertEqual(picker.searchQuery, "Ideas"); XCTAssertTrue(try store.collections().isEmpty)
        XCTAssertTrue(picker.handle(key(45, .command, "n")))
        picker.searchField.stringValue = "Ideas"
        XCTAssertTrue(picker.handle(key(36))); XCTAssertFalse(picker.creating)
        let folder = try XCTUnwrap(store.collections().first)
        XCTAssertEqual(folder.name, "Ideas"); XCTAssertFalse(try store.item(note.id)?.favorite == true)
        XCTAssertEqual(picker.choices[picker.table.selectedRow].id, folder.id)
        XCTAssertTrue(picker.handle(key(36)))
        XCTAssertEqual(try store.collections(for: note.id).map(\.id), [folder.id])
    }
    func testTagSearchAddsExistingTagToMixedSnapshotWithoutChangingFavorites() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let seed = try XCTUnwrap(store.captureText("tag seed"))
        try store.addTag("Çekim Fikirleri", to: [seed.id]); try store.addTag("Other", to: [seed.id])
        try store.addTag("IŞIK", to: [seed.id])
        let image = try store.captureImage(f.image()), text = try XCTUnwrap(store.captureText("tag snapshot"))
        let link = try store.captureLink(URL(string: "https://example.com/tag-snapshot")!)
        let ids = [image.id, text.id, link.id]
        let picker = try TagPicker(store: store, ids: ids + [text.id]); defer { picker.window.close() }
        XCTAssertEqual(Set(picker.ids), Set(ids))
        picker.setSearchQuery("ışık")
        XCTAssertEqual(picker.choices.map(\.title), ["IŞIK"]); XCTAssertFalse(picker.choices[0].isNew)
        picker.setSearchQuery("isik"); XCTAssertEqual(picker.choices.map(\.title), ["IŞIK"])
        picker.setSearchQuery("cekim fikir")
        XCTAssertEqual(picker.choices.first?.title, "Çekim Fikirleri")
        XCTAssertFalse(picker.choices.first?.isNew == true)
        XCTAssertTrue(picker.handle(key(36)))
        for id in ids {
            XCTAssertEqual(try store.tags(for: id).map(\.name), ["Çekim Fikirleri"])
            XCTAssertTrue(try store.item(id)?.retainedAt != nil)
            XCTAssertFalse(try store.item(id)?.favorite == true)
        }
    }
    func testTagCreationCancellationAndFailureDoNotPartiallyMutateBatch() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let first = try XCTUnwrap(store.captureText("first tagged")), second = try XCTUnwrap(store.captureText("second tagged"))
        let cancel = try TagPicker(store: store, ids: [first.id]); defer { cancel.window.close() }
        cancel.setSearchQuery("Cancelled"); XCTAssertTrue(cancel.handle(key(53)))
        XCTAssertTrue(try store.tags().isEmpty); XCTAssertNil(try store.item(first.id)?.retainedAt)
        let invalid = try TagPicker(store: store, ids: [first.id, UUID()]); defer { invalid.window.close() }
        invalid.setSearchQuery("Invalid batch"); XCTAssertTrue(invalid.handle(key(36)))
        XCTAssertTrue(try store.tags().isEmpty); XCTAssertNil(try store.item(first.id)?.retainedAt)
        let create = try TagPicker(store: store, ids: [first.id, second.id]); defer { create.window.close() }
        create.setSearchQuery("#Yeni fikir")
        XCTAssertTrue(create.choices.first?.isNew == true); XCTAssertEqual(create.choices.first?.title, "Yeni fikir")
        XCTAssertTrue(create.handle(key(36)))
        XCTAssertEqual(try store.tags().map(\.name), ["Yeni fikir"])
        for id in [first.id, second.id] { XCTAssertEqual(try store.tags(for: id).map(\.name), ["Yeni fikir"]) }
        let existing = try TagPicker(store: store, ids: [first.id]); defer { existing.window.close() }
        existing.setSearchQuery("#Yeni fikir"); XCTAssertEqual(existing.choices.count, 1); XCTAssertFalse(existing.choices[0].isNew)
    }
    func testPickerNativeFieldCommandsMoveResultsButLeaveTextEditingShortcutsAlone() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let seed = try XCTUnwrap(store.captureText("command routing"))
        for name in ["A tag", "B tag"] { try store.addTag(name, to: [seed.id]) }
        let picker = try TagPicker(store: store, ids: [seed.id]); defer { picker.window.close() }
        let editor = NSTextView()
        XCTAssertTrue(picker.control(picker.searchField, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        XCTAssertEqual(picker.table.selectedRow, 1)
        XCTAssertTrue(picker.control(picker.searchField, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:))))
        XCTAssertEqual(picker.table.selectedRow, 0)
        XCTAssertFalse(picker.control(picker.searchField, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
        XCTAssertFalse(picker.control(picker.searchField, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
        XCTAssertFalse(picker.handle(key(123))); XCTAssertFalse(picker.handle(key(124)))
        XCTAssertFalse(picker.handle(key(51))); XCTAssertFalse(picker.handle(key(1, [], "s")))
        XCTAssertFalse(picker.handle(key(123, .shift))); XCTAssertFalse(picker.handle(key(124, .shift)))
        XCTAssertFalse(picker.handle(key(125, .shift))); XCTAssertFalse(picker.handle(key(126, .shift)))
        XCTAssertEqual(picker.table.selectedRow, 0, "Shift-arrows belong to the native text editor, not the result list")
        XCTAssertFalse(picker.handle(key(8, .command, "c")))
        picker.searchField.stringValue = "B tag"
        picker.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: picker.searchField))
        XCTAssertEqual(picker.searchQuery, "B tag"); XCTAssertEqual(picker.choices.map(\.title), ["B tag"])
    }
}
