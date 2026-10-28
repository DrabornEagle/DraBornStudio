import AppKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class NameAndPinPickerTests: HistoryTestCase {
    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = [], _ text: String = "", isRepeat: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: text, charactersIgnoringModifiers: text, isARepeat: isRepeat, keyCode: code)!
    }

    func testNamePickerStartsWithCustomNameOnlyForEveryContentKind() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let text = try XCTUnwrap(store.captureText("synthetic-opaque-value-12345"))
        let image = try store.captureImage(f.image())
        let link = try store.captureLink(URL(string: "https://example.com/opaque-value-12345")!)
        try store.update(link.id) { $0.metadataTitle = "Generated metadata title" }
        for item in [text, image, link] {
            let picker = try NameAndPinPicker(store: store, id: item.id); defer { picker.window.close() }
            XCTAssertEqual(picker.id, item.id)
            XCTAssertEqual(picker.nameField.stringValue, "", "Copied values, paths and generated titles must not prefill a custom name")
            XCTAssertFalse(try store.item(item.id)?.favorite == true)
            XCTAssertNil(try store.item(item.id)?.retainedAt)
        }
        try store.update(text.id) { $0.title = "Existing İstanbul label" }
        let existing = try NameAndPinPicker(store: store, id: text.id); defer { existing.window.close() }
        XCTAssertEqual(existing.nameField.stringValue, "Existing İstanbul label")
        XCTAssertTrue(existing.nameField.isEditable); XCTAssertTrue(existing.nameField.isSelectable)
        XCTAssertEqual(existing.nameField.focusRingType, .none)
        XCTAssertFalse(existing.nameField.isBordered); XCTAssertFalse(existing.nameField.drawsBackground)
        XCTAssertFalse(existing.window.styleMask.contains(.titled))
        XCTAssertTrue(existing.window.frame.height < 260)
        XCTAssertNil(try? NameAndPinPicker(store: store, id: UUID()))
        try store.trash([link.id])
        XCTAssertNil(try? NameAndPinPicker(store: store, id: link.id))
    }

    func testNamePickerEnterPinsCapturedTargetAndLeavesOriginalAndOtherItemsUnchanged() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let target = try XCTUnwrap(store.captureText("synthetic-opaque-payload"))
        let other = try XCTUnwrap(store.captureText("another captured payload"))
        let picker = try NameAndPinPicker(store: store, id: target.id); defer { picker.window.close() }
        picker.nameField.stringValue = "  API deneme anahtarı 🔑  "
        XCTAssertTrue(picker.handle(key(36)))
        let saved = try XCTUnwrap(store.item(target.id))
        XCTAssertEqual(saved.title, "API deneme anahtarı 🔑")
        XCTAssertTrue(saved.favorite); XCTAssertTrue(saved.retainedAt != nil)
        XCTAssertEqual(saved.text, target.text); XCTAssertEqual(saved.createdAt, target.createdAt)
        XCTAssertEqual(try store.item(other.id), other)
        XCTAssertNil(picker.errorMessage)
        let rename = try NameAndPinPicker(store: store, id: target.id); defer { rename.window.close() }
        rename.nameField.stringValue = "API changed label"
        XCTAssertTrue(rename.handle(key(76)))
        XCTAssertEqual(try store.item(target.id)?.title, "API changed label")
        XCTAssertTrue(try store.item(target.id)?.favorite == true, "Renaming an existing pin must not toggle it off")
        XCTAssertEqual(try store.item(target.id)?.retainedAt, saved.retainedAt)
    }

    func testNamePickerEscapeCancelsWithoutPinningRetainingOrRenaming() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let target = try XCTUnwrap(store.captureText("cancelled name payload"))
        let picker = try NameAndPinPicker(store: store, id: target.id); defer { picker.window.close() }
        picker.nameField.stringValue = "Uncommitted label"
        XCTAssertTrue(picker.handle(key(53)))
        XCTAssertEqual(try store.item(target.id), target)
        let nativeCancel = try NameAndPinPicker(store: store, id: target.id); defer { nativeCancel.window.close() }
        nativeCancel.nameField.stringValue = "Another uncommitted label"
        XCTAssertTrue(nativeCancel.control(nativeCancel.nameField, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertEqual(try store.item(target.id), target)
    }

    func testNamePickerValidationLeavesDraftAndTargetIntactUntilCorrection() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let target = try XCTUnwrap(store.captureText("validation payload"))
        let picker = try NameAndPinPicker(store: store, id: target.id); defer { picker.window.close() }
        var closeCount = 0; picker.onClose = { closeCount += 1 }
        for invalid in ["   ", "first\nsecond", String(repeating: "a", count: 161)] {
            picker.nameField.stringValue = invalid
            XCTAssertTrue(picker.handle(key(36)))
            XCTAssertTrue(picker.errorMessage != nil); XCTAssertEqual(picker.nameField.stringValue, invalid)
            XCTAssertEqual(closeCount, 0, "Validation must leave the picker open")
            XCTAssertEqual(try store.item(target.id), target)
        }
        picker.nameField.stringValue = "Corrected label"
        picker.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: picker.nameField))
        XCTAssertNil(picker.errorMessage)
        XCTAssertTrue(picker.control(picker.nameField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(try store.item(target.id)?.title, "Corrected label")
        XCTAssertTrue(try store.item(target.id)?.favorite == true)
    }

    func testNamePickerNativeEditingKeysDoNotRunShelfCommands() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let target = try XCTUnwrap(store.captureText("native editing payload"))
        let picker = try NameAndPinPicker(store: store, id: target.id); defer { picker.window.close() }
        let editor = NSTextView()
        for event in [key(35, [], "p"), key(1, [], "s"), key(123), key(124), key(125), key(126), key(51),
            key(8, .command, "c"), key(0, .command, "a"), key(35, .option, "π"), key(123, .shift)] {
            XCTAssertFalse(picker.handle(event), "A name field owns native typing, arrows, selection and deletion")
        }
        for command in [#selector(NSResponder.moveLeft(_:)), #selector(NSResponder.moveRight(_:)), #selector(NSResponder.moveUp(_:)),
            #selector(NSResponder.moveDown(_:)), #selector(NSResponder.deleteBackward(_:))] {
            XCTAssertFalse(picker.control(picker.nameField, textView: editor, doCommandBy: command))
        }
        picker.nameField.stringValue = "Typed p s arrows"
        picker.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: picker.nameField))
        XCTAssertEqual(try store.item(target.id), target)
    }

    func testNamePickerFocusSelectsCustomNameAndNativeCompositionDoesNotSave() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let target = try XCTUnwrap(store.captureText("native composition payload"))
        try store.update(target.id) { $0.title = "Existing custom label" }
        let before = try XCTUnwrap(store.item(target.id))
        let picker = try NameAndPinPicker(store: store, id: target.id); defer { picker.window.close() }
        picker.window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        picker.window.contentView?.layoutSubtreeIfNeeded()
        picker.focusName()
        let editor = try XCTUnwrap(picker.nameField.currentEditor() as? NSTextView)
        XCTAssertTrue(picker.window.firstResponder === editor)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: (before.title as NSString).length))
        editor.setMarkedText("仮", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertFalse(picker.handle(key(36))); XCTAssertFalse(picker.handle(key(53)))
        XCTAssertFalse(picker.control(picker.nameField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(try store.item(target.id), before)
        editor.unmarkText()
        XCTAssertFalse(editor.hasMarkedText())
        XCTAssertTrue(picker.handle(key(53)))
        XCTAssertEqual(try store.item(target.id), before)
    }

    func testBatchNamePickerFreezesFirstSeenOrderAndRejectsInvalidSelectionUpfront() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let first = try XCTUnwrap(store.captureText("first private synthetic payload"))
        let second = try store.captureLink(URL(string: "https://example.com/second")!)
        let picker = try NameAndPinPicker(store: store, ids: [second.id, first.id, second.id, first.id])
        defer { picker.window.close() }
        XCTAssertEqual(picker.orderedIDs, [second.id, first.id]); XCTAssertEqual(picker.id, second.id)
        XCTAssertEqual(picker.currentIndex, 0); XCTAssertEqual(picker.progressText, String(format: L("Item %d of %d"), 1, 2))
        XCTAssertNil(try? NameAndPinPicker(store: store, ids: []))
        XCTAssertNil(try? NameAndPinPicker(store: store, ids: [first.id, UUID()]))
        try store.trash([second.id])
        XCTAssertNil(try? NameAndPinPicker(store: store, ids: [first.id, second.id]))
        XCTAssertEqual(try store.item(first.id), first, "Validation must not pin a valid prefix before rejecting a bad target")
    }

    func testBatchNamePickerEnterAdvancesSameWindowAndSelectsEachExistingName() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let first = try XCTUnwrap(store.captureText("opaque first value"))
        let second = try store.captureImage(f.image(name: "Settings screenshot.png"))
        try store.update(second.id) { $0.title = "Existing second name" }
        let third = try store.captureLink(URL(string: "https://example.com/third")!)
        let picker = try NameAndPinPicker(store: store, ids: [first.id, second.id, third.id])
        defer { picker.window.close() }
        picker.window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        picker.window.contentView?.layoutSubtreeIfNeeded(); picker.focusName()
        let window = picker.window
        var advanced = [UUID](), closeCount = 0
        picker.onAdvance = { advanced.append($0) }; picker.onClose = { closeCount += 1 }
        picker.nameField.stringValue = "First name"
        XCTAssertTrue(picker.handle(key(36)))
        XCTAssertTrue(picker.window === window); XCTAssertEqual(closeCount, 0)
        XCTAssertEqual(picker.id, second.id); XCTAssertEqual(picker.currentIndex, 1)
        XCTAssertEqual(picker.nameField.stringValue, "Existing second name")
        let editor = try XCTUnwrap(picker.nameField.currentEditor() as? NSTextView)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: ("Existing second name" as NSString).length))
        XCTAssertTrue(try store.item(first.id)?.favorite == true)
        XCTAssertFalse(try store.item(second.id)?.favorite == true, "Loading the next name must not prematurely pin it")
        picker.nameField.stringValue = "Second name"
        XCTAssertTrue(picker.handle(key(76)))
        XCTAssertEqual(picker.id, third.id); XCTAssertEqual(advanced, [second.id, third.id])
        XCTAssertEqual(picker.progressText, String(format: L("Item %d of %d"), 3, 3))
        picker.nameField.stringValue = "Third name"
        XCTAssertTrue(picker.control(picker.nameField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(closeCount, 1)
        XCTAssertEqual(try store.item(first.id)?.title, "First name")
        XCTAssertEqual(try store.item(second.id)?.title, "Second name")
        XCTAssertEqual(try store.item(third.id)?.title, "Third name")
        XCTAssertEqual(try store.item(first.id)?.text, first.text)
        XCTAssertEqual(try store.item(third.id)?.originalURL, third.originalURL)
        for id in picker.orderedIDs { XCTAssertTrue(try store.item(id)?.favorite == true) }
    }

    func testBatchNamePickerEscapeKeepsCompletedNamesAndLeavesRemainderUntouched() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let first = try XCTUnwrap(store.captureText("first payload"))
        let second = try XCTUnwrap(store.captureText("second payload"))
        let third = try store.captureLink(URL(string: "https://example.com/third")!)
        let picker = try NameAndPinPicker(store: store, ids: [first.id, second.id, third.id])
        defer { picker.window.close() }
        var closeCount = 0; picker.onClose = { closeCount += 1 }
        picker.nameField.stringValue = "Completed first"
        XCTAssertTrue(picker.handle(key(36)))
        let committed = try XCTUnwrap(store.item(first.id))
        picker.nameField.stringValue = "Uncommitted second"
        XCTAssertTrue(picker.handle(key(53)))
        XCTAssertEqual(closeCount, 1); XCTAssertEqual(try store.item(first.id), committed)
        XCTAssertTrue(committed.favorite); XCTAssertEqual(committed.title, "Completed first")
        XCTAssertEqual(try store.item(second.id), second); XCTAssertEqual(try store.item(third.id), third)
        XCTAssertTrue(picker.handle(key(36)), "An already closed picker consumes a late Enter without mutating anything")
        XCTAssertEqual(try store.item(second.id), second); XCTAssertEqual(closeCount, 1)
    }

    func testBatchNamePickerInvalidNameAndFailedSaveStayOnCurrentTarget() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let first = try XCTUnwrap(store.captureText("database rejection payload"))
        let second = try XCTUnwrap(store.captureText("untouched second payload"))
        let database = try LibraryDatabase(url: store.databaseURL)
        let picker = try NameAndPinPicker(store: store, ids: [first.id, second.id])
        defer { picker.window.close() }
        var advanced = [UUID](); picker.onAdvance = { advanced.append($0) }
        picker.nameField.stringValue = "   "
        XCTAssertTrue(picker.handle(key(36)))
        XCTAssertNotNil(picker.errorMessage); XCTAssertEqual(picker.id, first.id); XCTAssertEqual(advanced, [])
        try database.execute("CREATE TRIGGER reject_batch_name BEFORE UPDATE ON items WHEN NEW.favorite=1 BEGIN SELECT RAISE(ABORT,'synthetic name rejection'); END")
        picker.nameField.stringValue = "Valid but rejected"
        XCTAssertTrue(picker.handle(key(36)))
        XCTAssertNotNil(picker.errorMessage); XCTAssertEqual(picker.nameField.stringValue, "Valid but rejected")
        XCTAssertEqual(picker.id, first.id); XCTAssertEqual(picker.currentIndex, 0); XCTAssertEqual(advanced, [])
        XCTAssertEqual(try store.item(first.id), first); XCTAssertEqual(try store.item(second.id), second)
        try database.execute("DROP TRIGGER reject_batch_name")
        XCTAssertTrue(picker.handle(key(36)))
        XCTAssertNil(picker.errorMessage); XCTAssertEqual(picker.id, second.id); XCTAssertEqual(advanced, [second.id])
        XCTAssertEqual(try store.item(first.id)?.title, "Valid but rejected")
        XCTAssertEqual(try store.item(second.id), second)
    }

    func testBatchNamePickerSkipsFutureDeletedItemAndNeverRevivesDeletedCurrentItem() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let first = try XCTUnwrap(store.captureText("first deletion fixture"))
        let second = try XCTUnwrap(store.captureText("second deletion fixture"))
        let third = try XCTUnwrap(store.captureText("third deletion fixture"))
        let picker = try NameAndPinPicker(store: store, ids: [first.id, second.id, third.id])
        defer { picker.window.close() }
        var advanced = [UUID](); picker.onAdvance = { advanced.append($0) }
        try store.trash([second.id])
        let deleted = try XCTUnwrap(store.item(second.id))
        picker.nameField.stringValue = "First completed"
        XCTAssertTrue(picker.handle(key(36)))
        XCTAssertEqual(picker.id, third.id); XCTAssertEqual(picker.currentIndex, 2)
        XCTAssertEqual(advanced, [third.id]); XCTAssertEqual(try store.item(second.id), deleted)
        try store.trash([third.id])
        let currentDeleted = try XCTUnwrap(store.item(third.id))
        picker.nameField.stringValue = "Must not revive"
        XCTAssertTrue(picker.handle(key(36)))
        XCTAssertEqual(picker.errorMessage, L("This item is no longer available. Press Esc to leave.")); XCTAssertEqual(picker.id, third.id)
        XCTAssertEqual(try store.item(third.id), currentDeleted)
        XCTAssertEqual(advanced, [third.id])
    }

    func testBatchNamePickerRepeatedAndReentrantEnterCannotDoubleAdvance() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let records = try (1...3).map { try XCTUnwrap(store.captureText("repeat payload \($0)")) }
        try store.update(records[1].id) { $0.title = "Existing second" }
        let secondBefore = try XCTUnwrap(store.item(records[1].id))
        let picker = try NameAndPinPicker(store: store, ids: records.map(\.id))
        defer { picker.window.close() }
        var advanceCount = 0
        picker.onAdvance = { _ in
            advanceCount += 1
            XCTAssertTrue(picker.handle(self.key(36)), "A reentrant handler must consume but not accept the next target")
        }
        picker.nameField.stringValue = "First saved"
        let enter = key(36)
        XCTAssertTrue(picker.handle(enter)); XCTAssertEqual(picker.id, records[1].id)
        XCTAssertTrue(picker.handle(enter)); XCTAssertEqual(picker.id, records[1].id)
        XCTAssertTrue(picker.handle(key(36, isRepeat: true))); XCTAssertEqual(picker.id, records[1].id)
        XCTAssertEqual(advanceCount, 1); XCTAssertEqual(try store.item(records[1].id), secondBefore)
        picker.nameField.stringValue = "Second saved"
        XCTAssertTrue(picker.handle(key(36)))
        XCTAssertEqual(picker.id, records[2].id); XCTAssertEqual(advanceCount, 2)
        XCTAssertEqual(try store.item(records[1].id)?.title, "Second saved")
        XCTAssertFalse(try store.item(records[2].id)?.favorite == true)
    }

    func testBatchNamePickerContextIdentifiesKindsWithoutDisplayingOpaqueTextOrURLSecrets() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let text = try XCTUnwrap(store.captureText("synthetic-private-opaque-value"))
        let image = try store.captureImage(f.image(name: "Settings reference.png"))
        let link = try store.captureLink(URL(string: "https://example.com/synthetic-secret-path?token=synthetic-secret")!)
        try store.update(link.id) { $0.metadataTitle = "Reference video" }
        let picker = try NameAndPinPicker(store: store, ids: [text.id, image.id, link.id])
        defer { picker.window.close() }
        XCTAssertEqual(picker.itemContext, L("Text") + " · " + L("Untitled note"))
        XCTAssertFalse(picker.itemContext.contains("synthetic-private"))
        picker.nameField.stringValue = "Named secret"
        XCTAssertTrue(picker.handle(key(36)))
        XCTAssertEqual(picker.itemContext, L("Image") + " · Settings reference.png")
        picker.nameField.stringValue = "Named screenshot"
        XCTAssertTrue(picker.handle(key(36)))
        XCTAssertEqual(picker.itemContext, L("Link") + " · Reference video · example.com")
        XCTAssertFalse(picker.itemContext.contains("synthetic-secret"))
    }

    func testBatchNamePickerAdvancingPreservesNativeCompositionOnNextDraft() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let first = try XCTUnwrap(store.captureText("first composition fixture"))
        let second = try XCTUnwrap(store.captureText("second composition fixture"))
        try store.update(second.id) { $0.title = "既存名" }
        let before = try XCTUnwrap(store.item(second.id))
        let picker = try NameAndPinPicker(store: store, ids: [first.id, second.id])
        defer { picker.window.close() }
        picker.window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        picker.window.contentView?.layoutSubtreeIfNeeded(); picker.focusName()
        picker.nameField.stringValue = "Completed first"
        XCTAssertTrue(picker.handle(key(36))); XCTAssertEqual(picker.id, second.id)
        let editor = try XCTUnwrap(picker.nameField.currentEditor() as? NSTextView)
        editor.setMarkedText("仮", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertFalse(picker.handle(key(36))); XCTAssertFalse(picker.handle(key(53)))
        XCTAssertFalse(picker.control(picker.nameField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertFalse(picker.control(picker.nameField, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertEqual(try store.item(second.id), before)
        XCTAssertEqual(try store.item(first.id)?.title, "Completed first")
        editor.unmarkText()
        XCTAssertTrue(picker.handle(key(53)))
        XCTAssertEqual(try store.item(second.id), before)
    }

    func testBatchNamePickerButtonAndMouseEventSaveWithoutKeyboardOnlyProperties() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let first = try XCTUnwrap(store.captureText("mouse action first payload"))
        let second = try XCTUnwrap(store.captureText("mouse action second payload"))
        let picker = try NameAndPinPicker(store: store, ids: [first.id, second.id])
        defer { picker.window.close() }
        picker.nameField.stringValue = "Saved from mouse event"
        let mouseUp = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: picker.window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
        picker.confirm(event: mouseUp)
        XCTAssertEqual(try store.item(first.id)?.title, "Saved from mouse event")
        XCTAssertTrue(try store.item(first.id)?.favorite == true)
        XCTAssertEqual(picker.id, second.id)
        picker.confirm(event: mouseUp)
        XCTAssertEqual(try store.item(second.id), second, "Duplicate delivery must not commit the next target")
        func buttons(in view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
        }
        let save = try XCTUnwrap(picker.window.contentView.flatMap { buttons(in: $0).first { $0.title == L("Pin with name") } })
        picker.nameField.stringValue = "Saved by actual button action"
        save.performClick(nil)
        XCTAssertEqual(try store.item(second.id)?.title, "Saved by actual button action")
        XCTAssertTrue(try store.item(second.id)?.favorite == true)
    }
}
