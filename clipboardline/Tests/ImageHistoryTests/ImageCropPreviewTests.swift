import AppKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class ImageCropPreviewTests: HistoryTestCase {
    private func image(_ fixture: SyntheticFixture) throws -> URL {
        let url = try fixture.image()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 400,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        if let data = bitmap.bitmapData { memset(data, 255, bitmap.bytesPerRow * bitmap.pixelsHigh) }
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        return url
    }
    private func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [], text: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
            isARepeat: false, keyCode: code)!
    }
    private func chooseCrop(_ preview: ImagePreview) {
        let canvas = preview.canvas
        for (type, x, y) in [(NSEvent.EventType.leftMouseDown, 0.2, 0.25), (.leftMouseDragged, 0.8, 0.75), (.leftMouseUp, 0.8, 0.75)] {
            let point = NSPoint(x: canvas.bounds.minX + canvas.bounds.width * x, y: canvas.bounds.minY + canvas.bounds.height * y)
            let event = NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: preview.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            switch type {
            case .leftMouseDown: canvas.mouseDown(with: event)
            case .leftMouseDragged: canvas.mouseDragged(with: event)
            default: canvas.mouseUp(with: event)
            }
        }
    }
    func testCropShortcutAppliesAndSavesThenReturnsToBrowsingInSameWindow() throws {
        _ = NSApplication.shared
        let fixture = try SyntheticFixture(); defer { fixture.cleanup() }
        let url = try image(fixture), original = try Data(contentsOf: url)
        let preview = try XCTUnwrap(ImagePreview(url: url, keyboardBindings: KeyboardBindings(defaults: fixture.defaults)))
        defer { preview.requestClose() }
        var saved = [ImageMarkupDocument]()
        preview.onSaveMarkup = { saved.append($0); return true }
        let number = preview.window.windowNumber
        XCTAssertTrue(preview.routeKey(key(8, text: "c"))); XCTAssertTrue(preview.isCropping)
        XCTAssertTrue(preview.toolbar.isCropping); XCTAssertTrue(preview.controls.leadingAccessory === preview.toolbar)
        chooseCrop(preview)
        XCTAssertTrue(preview.routeKey(key(36)))
        XCTAssertEqual(saved.count, 1); XCTAssertNotNil(saved[0].crop)
        XCTAssertFalse(preview.isCropping); XCTAssertFalse(preview.isMarkupEditing)
        XCTAssertFalse(preview.hasUnsavedMarkup); XCTAssertEqual(preview.window.windowNumber, number)
        XCTAssertTrue(abs(preview.window.frame.width / preview.window.frame.height - 1.8) < 0.01)
        XCTAssertTrue(preview.routeKey(key(6, flags: .command, text: "z")))
        XCTAssertNil(preview.document.crop); XCTAssertEqual(saved.count, 2)
        XCTAssertFalse(preview.isMarkupEditing)
        XCTAssertTrue(preview.routeKey(key(6, flags: [.command, .shift], text: "z")))
        XCTAssertNotNil(preview.document.crop); XCTAssertEqual(saved.count, 3)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
    func testCropEscapeAndNoOpEnterDoNotSaveOrAlterExistingCrop() throws {
        _ = NSApplication.shared
        let fixture = try SyntheticFixture(); defer { fixture.cleanup() }
        let url = try image(fixture), preview = try XCTUnwrap(ImagePreview(url: url))
        defer { preview.requestClose() }
        let document = ImageMarkupDocument(crop: MarkupCrop(x: 0.1, y: 0.2, width: 0.6, height: 0.5))
        preview.configureMarkup(document: document, sourceURL: url)
        var saves = 0; preview.onSaveMarkup = { _ in saves += 1; return true }
        preview.beginCrop(); chooseCrop(preview)
        XCTAssertTrue(preview.routeKey(key(53)))
        XCTAssertEqual(preview.document, document); XCTAssertEqual(saves, 0)
        XCTAssertFalse(preview.isCropping); XCTAssertFalse(preview.isMarkupEditing)
        preview.beginCrop()
        XCTAssertTrue(preview.routeKey(key(36)))
        XCTAssertEqual(preview.document, document); XCTAssertEqual(saves, 0)
        XCTAssertFalse(preview.isMarkupEditing)
    }
    func testCropUndoRedoPreservesAnnotationsAndRefitsEditingCanvas() throws {
        _ = NSApplication.shared
        let fixture = try SyntheticFixture(); defer { fixture.cleanup() }
        let url = try image(fixture), preview = try XCTUnwrap(ImagePreview(url: url))
        defer { preview.onSaveMarkup = { _ in true }; preview.requestClose() }
        let document = ImageMarkupDocument(elements: [.init(tool: .line, points: [.init(x: 0.1, y: 0.5), .init(x: 0.9, y: 0.5)])])
        preview.configureMarkup(document: document, sourceURL: url); preview.onSaveMarkup = { _ in true }
        preview.beginMarkup(); preview.beginCrop(); chooseCrop(preview)
        XCTAssertTrue(preview.applyCrop()); XCTAssertTrue(preview.isMarkupEditing)
        let crop = try XCTUnwrap(preview.document.crop)
        XCTAssertEqual(preview.document.elements, document.elements)
        XCTAssertTrue(abs(preview.scroll.frame.width / preview.scroll.frame.height - 1.8) < 0.01)
        XCTAssertTrue(preview.performMarkupCommand(.undo)); XCTAssertNil(preview.document.crop)
        XCTAssertTrue(abs(preview.scroll.frame.width / preview.scroll.frame.height - 1.5) < 0.01)
        XCTAssertTrue(preview.performMarkupCommand(.redo)); XCTAssertEqual(preview.document.crop, crop)
        XCTAssertEqual(preview.document.elements, document.elements)
        XCTAssertTrue(abs(preview.scroll.frame.width / preview.scroll.frame.height - 1.8) < 0.01)
    }
    func testLeavingCropFlushesChosenAreaAndFailedSaveRetainsRetryableDocument() throws {
        _ = NSApplication.shared
        let fixture = try SyntheticFixture(); defer { fixture.cleanup() }
        let preview = try XCTUnwrap(ImagePreview(url: image(fixture)))
        defer { preview.onSaveMarkup = { _ in true }; preview.requestClose() }
        var saved = [ImageMarkupDocument]()
        preview.onSaveMarkup = { saved.append($0); return false }
        preview.beginCrop(); chooseCrop(preview)
        XCTAssertFalse(preview.flushEdits()); XCTAssertFalse(preview.isCropping)
        XCTAssertNotNil(preview.document.crop); XCTAssertTrue(preview.hasUnsavedMarkup)
        XCTAssertEqual(saved.count, 1)
        preview.onSaveMarkup = { saved.append($0); return true }
        XCTAssertTrue(preview.flushEdits()); XCTAssertFalse(preview.hasUnsavedMarkup)
        XCTAssertEqual(saved.count, 2); XCTAssertEqual(saved[0], saved[1])
    }
    func testCropToolbarCanResetAndApplyToRestoreFullOriginal() throws {
        _ = NSApplication.shared
        let fixture = try SyntheticFixture(); defer { fixture.cleanup() }
        let url = try image(fixture), preview = try XCTUnwrap(ImagePreview(url: url))
        defer { preview.requestClose() }
        preview.configureMarkup(document: .init(crop: .init(x: 0.1, y: 0.2, width: 0.6, height: 0.5)), sourceURL: url)
        var saved: ImageMarkupDocument?
        preview.onSaveMarkup = { saved = $0; return true }
        preview.beginCrop()
        preview.toolbar.resetCropButton.performClick(nil)
        XCTAssertEqual(preview.canvas.cropSelection, .full)
        preview.toolbar.applyCropButton.performClick(nil)
        XCTAssertNil(preview.document.crop); XCTAssertNotNil(saved); XCTAssertTrue(saved?.isEmpty == true)
        XCTAssertFalse(preview.isCropping); XCTAssertFalse(preview.isMarkupEditing)
    }
    func testActionBarCropOpensCapturedShelfImageDirectly() throws {
        _ = NSApplication.shared
        let fixture = try SyntheticFixture(); defer { fixture.cleanup() }
        let store = try LibraryStore(defaults: fixture.defaults, inbox: fixture.inbox, now: { fixture.date })
        let line = Line(defaults: fixture.defaults, inbox: fixture.inbox, now: { fixture.date }, breeze: false,
            copyImage: { _ in }, copyText: { _ in }, library: store)
        let id = try XCTUnwrap(line.hang(image(fixture), quietly: true))
        line.select(id)
        let delegate = AppDelegate(line: line, watchesFiles: false)
        defer { delegate.commandPalette?.window.close(); delegate.preview?.requestClose() }
        delegate.showCommands(origin: .line)
        let palette = try XCTUnwrap(delegate.commandPalette)
        let index = try XCTUnwrap(palette.visibleCommands.firstIndex { $0.id == KeyboardAction.cropImage.rawValue })
        XCTAssertTrue(palette.visibleCommands[index].isEnabled)
        palette.table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false); palette.executeSelected()
        XCTAssertEqual(delegate.previewSession?.currentID, id)
        XCTAssertTrue(delegate.preview?.isCropping == true)
        delegate.preview?.cancelCrop()
    }
}
