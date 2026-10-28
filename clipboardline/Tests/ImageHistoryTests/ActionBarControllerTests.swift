import AppKit
import Carbon
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class ActionBarControllerTests: HistoryTestCase {
    private func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [], text: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
            isARepeat: false, keyCode: code)!
    }
    private func wait(_ predicate: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !predicate() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(predicate(), "Action bar fixture did not settle")
    }
    private func image(_ fixture: SyntheticFixture) throws -> URL {
        let url = try fixture.image()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 200,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        if let bytes = bitmap.bitmapData { memset(bytes, 255, bitmap.bytesPerRow * bitmap.pixelsHigh) }
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        return url
    }
    private func draw(_ preview: ImagePreview) {
        let canvas = preview.canvas
        for (type, point) in [(NSEvent.EventType.leftMouseDown, NSPoint(x: canvas.bounds.width * 0.2, y: canvas.bounds.height * 0.2)),
                              (.leftMouseDragged, NSPoint(x: canvas.bounds.width * 0.8, y: canvas.bounds.height * 0.8)),
                              (.leftMouseUp, NSPoint(x: canvas.bounds.width * 0.8, y: canvas.bounds.height * 0.8))] {
            let event = NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: preview.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            if type == .leftMouseDown { canvas.mouseDown(with: event) }
            else if type == .leftMouseDragged { canvas.mouseDragged(with: event) }
            else { canvas.mouseUp(with: event) }
        }
    }

    func testShelfCommandsOpenWhileSearchingAndPlainRemappedKeysStillType() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let line = Line(defaults: f.defaults, inbox: f.inbox, breeze: false,
            copyImage: { _ in }, copyText: { _ in }, library: store)
        let keyboard = LineKeyboard(line: line, onCopy: { _ in }, onPreview: { _ in }, onClose: {})
        var opened = 0; line.onCommandsRequested = { opened += 1 }
        XCTAssertTrue(keyboard.perform(.searchShelf)); XCTAssertNotNil(line.searchEditingShelf)
        XCTAssertTrue(keyboard.handle(key(40, flags: .command, text: "k"))); XCTAssertEqual(opened, 1)
        XCTAssertFalse(keyboard.handle(key(35, text: "p")))
        try line.keyboardBindings.set([KeyShortcut(keyCode: 40, modifiers: 0, keyLabel: "K")], for: .commandPalette)
        XCTAssertFalse(keyboard.handle(key(40, text: "k"))); XCTAssertEqual(opened, 1)
        XCTAssertTrue(keyboard.perform(.commandPalette)); XCTAssertEqual(opened, 2)
        XCTAssertFalse(keyboard.perform(.markupMarker))
    }

    func testLibraryExplicitActionsShareSelectionAndLeaveNativeEditingKeysAlone() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let record = try XCTUnwrap(store.captureText("Action bar note"))
        let board = NSPasteboard(name: NSPasteboard.Name("action-bar-model-\(UUID())"))
        let model = LibraryModel(store: store, copyPasteboard: board); model.changeScope(.recent)
        wait { model.ids == [record.id] && !model.loading }
        XCTAssertTrue(model.select(record.id))
        var opened = 0; model.onCommandsRequested = { opened += 1 }
        XCTAssertTrue(model.handleKey(key(40, flags: .command, text: "k"), editing: true)); XCTAssertEqual(opened, 1)
        XCTAssertFalse(model.handleKey(key(35, text: "p"), editing: true)); XCTAssertFalse(try XCTUnwrap(store.item(record.id)).favorite)
        XCTAssertTrue(model.perform(.pin)); XCTAssertTrue(try XCTUnwrap(store.item(record.id)).favorite)
        XCTAssertTrue(model.perform(.copy)); XCTAssertEqual(board.string(forType: .string), "Action bar note")
        try model.keyboardBindings.set([KeyShortcut(keyCode: 40, modifiers: 0, keyLabel: "K")], for: .commandPalette)
        XCTAssertFalse(model.handleKey(key(40, text: "k"), editing: true)); XCTAssertEqual(opened, 1)
        XCTAssertFalse(model.perform(.markupMarker))
    }

    func testMarkerActionOpensEditingAndMenuCommandsPreserveFailedSaveDraft() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let preview = try XCTUnwrap(ImagePreview(url: image(f), keyboardBindings: KeyboardBindings(defaults: f.defaults)))
        defer { preview.onSaveMarkup = { _ in true }; preview.requestClose() }
        XCTAssertTrue(preview.perform(.markupMarker)); XCTAssertTrue(preview.isMarkupEditing)
        XCTAssertEqual(preview.canvas.tool, .marker); XCTAssertEqual(preview.canvas.color, .yellow)
        draw(preview)
        let draft = preview.document; XCTAssertEqual(draft.elements.count, 1)
        XCTAssertTrue(preview.performMarkupCommand(.undo)); XCTAssertTrue(preview.document.isEmpty)
        XCTAssertTrue(preview.performMarkupCommand(.redo)); XCTAssertEqual(preview.document, draft)
        preview.onSaveMarkup = { _ in false }
        XCTAssertFalse(preview.performMarkupCommand(.finishEditing)); XCTAssertTrue(preview.isMarkupEditing)
        XCTAssertEqual(preview.document, draft); XCTAssertTrue(preview.hasUnsavedMarkup)
        preview.onSaveMarkup = { _ in true }
        XCTAssertTrue(preview.performMarkupCommand(.save)); XCTAssertFalse(preview.hasUnsavedMarkup)
        XCTAssertTrue(preview.performMarkupCommand(.finishEditing)); XCTAssertFalse(preview.isMarkupEditing)
        XCTAssertTrue(preview.performMarkupCommand(.resetZoom))
    }

    func testLibraryPreviewActionsKeepCapturedRecordSeparateFromGridSelection() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let grid = try XCTUnwrap(store.captureText("Grid selection"))
        let shown = try XCTUnwrap(store.captureText("Preview selection"))
        let photo = try store.captureImage(image(f))
        let controller = LibraryWindowController(store: store,
            line: Line(defaults: f.defaults, inbox: f.inbox, breeze: false, library: store),
            copyPasteboard: NSPasteboard(name: NSPasteboard.Name("action-bar-preview-\(UUID())")))
        defer { controller.dismissPreviews(); controller.window?.contentViewController = nil }
        controller.model.changeScope(.recent); wait { controller.model.ids.count == 3 && !controller.model.loading }
        XCTAssertTrue(controller.model.select(grid.id))
        XCTAssertTrue(controller.performPreviewAction(.editText, id: shown.id))
        XCTAssertEqual(controller.previewCurrentID, shown.id); XCTAssertTrue(controller.previewTextIsEditing)
        XCTAssertEqual(controller.model.actionIDs, [grid.id])
        XCTAssertTrue(controller.performPreviewAction(.finishEditing, id: shown.id)); XCTAssertFalse(controller.previewTextIsEditing)
        XCTAssertTrue(controller.performPreviewAction(.markupMarker, id: photo.id))
        XCTAssertEqual(controller.previewCurrentID, photo.id); XCTAssertEqual(controller.previewImage?.canvas.tool, .marker)
        XCTAssertEqual(controller.model.actionIDs, [grid.id])
        XCTAssertTrue(controller.performMarkupCommand(.finishEditing, id: photo.id))
        XCTAssertTrue(controller.performPreviewNavigation(.last))
        XCTAssertEqual(controller.previewCurrentID, controller.model.ids.last)
    }

    func testDiscoverableCommandsControlsUseCurrentBindingsWithoutChangingRecords() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let bindings = KeyboardBindings(defaults: f.defaults), controls = PreviewControls(markup: true)
        controls.keyboardBindings = bindings
        var opened = 0; controls.onCommands = { opened += 1 }
        controls.actionsButton.performClick(nil); XCTAssertEqual(opened, 1)
        XCTAssertTrue(controls.actionsButton.toolTip?.contains("⌘K") == true)
        try bindings.set([KeyShortcut(keyCode: 40, modifiers: cmdKey | shiftKey, keyLabel: "K")], for: .commandPalette)
        controls.update(position: "1 / 1", pinned: false)
        XCTAssertTrue(controls.actionsButton.toolTip?.contains("⇧⌘K") == true)
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let record = try XCTUnwrap(store.captureText("Actions control leaves this note intact"))
        let before = try store.item(record.id)
        let controller = LibraryWindowController(store: store, line: Line(defaults: f.defaults, inbox: f.inbox, breeze: false, library: store))
        defer { controller.window?.contentViewController = nil }
        let item = try XCTUnwrap(controller.window?.toolbar?.items.first { $0.itemIdentifier == LibraryToolbarController.commandID })
        XCTAssertTrue(item.toolTip?.contains("⇧⌘K") == true)
        controller.model.onCommandsRequested = { opened += 1 }
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item)); XCTAssertEqual(opened, 2)
        XCTAssertEqual(try store.item(record.id), before)
    }

    func testDetailsRevealUsesCapturedRecordAcrossFiltersAndRetainedScopes() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox)
        let saved = try XCTUnwrap(store.captureText("Favorite target"))
        let recent = try XCTUnwrap(store.captureText("Recent target"))
        let trashed = try XCTUnwrap(store.captureText("Trash target"))
        try store.retain([saved.id]); try store.trash([trashed.id])
        let controller = LibraryWindowController(store: store, line: Line(defaults: f.defaults, inbox: f.inbox, breeze: false, library: store))
        defer { controller.dismissPreviews(); controller.window?.contentViewController = nil }
        let model = controller.model
        model.changeScope(.recent); model.setKind(.link)
        wait { !model.loading && model.ids.isEmpty }
        controller.revealItemDetails(saved.id)
        wait { !model.loading && model.focusedID == saved.id }
        XCTAssertEqual(model.query.scope, .saved); XCTAssertFalse(model.query.hasFilters); XCTAssertTrue(model.inspectorVisible)
        model.setKind(.text); model.search = "Favorite target"
        wait { !model.loading && model.query.search == "Favorite target" && model.ids == [saved.id] }
        let matchingQuery = model.query
        model.inspectorVisible = false
        controller.revealItemDetails(saved.id)
        XCTAssertEqual(model.query, matchingQuery); XCTAssertTrue(model.inspectorVisible)
        model.search = "unmatched text"
        wait { !model.loading && model.query.search == "unmatched text" && model.ids.isEmpty }
        controller.revealItemDetails(recent.id)
        wait { !model.loading && model.focusedID == recent.id }
        XCTAssertEqual(model.query.scope, .recent); XCTAssertFalse(model.query.hasFilters)
        controller.revealItemDetails(trashed.id)
        wait { !model.loading && model.focusedID == trashed.id }
        XCTAssertEqual(model.query.scope, .trash)
        // A subsequent user filter wins over an asynchronous command reveal.
        controller.revealItemDetails(saved.id); model.setKind(.link)
        wait { !model.loading && model.ids.isEmpty }
        XCTAssertEqual(model.query.kind, .link); XCTAssertNil(model.focusedID)
    }
}
