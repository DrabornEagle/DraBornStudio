import AppKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class ImageCropCanvasTests: HistoryTestCase {
    private func mouse(_ type: NSEvent.EventType, _ point: NSPoint, canvas: ImageMarkupCanvas) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: canvas.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    private func drag(_ canvas: ImageMarkupCanvas, _ start: NSPoint, _ end: NSPoint, finish: Bool = true) {
        canvas.mouseDown(with: mouse(.leftMouseDown, start, canvas: canvas))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, end, canvas: canvas))
        if finish { canvas.mouseUp(with: mouse(.leftMouseUp, end, canvas: canvas)) }
    }
    private func click(_ canvas: ImageMarkupCanvas, _ point: NSPoint) {
        canvas.mouseDown(with: mouse(.leftMouseDown, point, canvas: canvas))
        canvas.mouseUp(with: mouse(.leftMouseUp, point, canvas: canvas))
    }
    private func withCanvas(_ body: (ImageMarkupCanvas) throws -> Void) rethrows {
        _ = NSApplication.shared
        let canvas = ImageMarkupCanvas(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
        let window = NSWindow(contentRect: canvas.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.close() }; try body(canvas)
    }
    private var mark: ImageMarkupElement {
        ImageMarkupElement(tool: .rectangle, points: [.init(x: 0.35, y: 0.35), .init(x: 0.55, y: 0.55)], fill: true)
    }
    private var halfCrop: MarkupCrop { .init(x: 0.25, y: 0.25, width: 0.5, height: 0.5) }
    private func assertCrop(_ actual: MarkupCrop?, _ expected: MarkupCrop, file: StaticString = #filePath, line: UInt = #line) throws {
        let actual = try XCTUnwrap(actual, file: file, line: line)
        XCTAssertTrue(abs(actual.x - expected.x) < 0.000001, file: file, line: line)
        XCTAssertTrue(abs(actual.y - expected.y) < 0.000001, file: file, line: line)
        XCTAssertTrue(abs(actual.width - expected.width) < 0.000001, file: file, line: line)
        XCTAssertTrue(abs(actual.height - expected.height) < 0.000001, file: file, line: line)
        XCTAssertTrue(actual.isValid, file: file, line: line)
    }

    func testCropDraftAppliesOnceAndUndoRedoKeepOriginalMarks() throws {
        try withCanvas { canvas in
            let original = ImageMarkupDocument(elements: [mark]); canvas.load(original)
            var changes = 0; canvas.onChange = { changes += 1 }
            canvas.beginCrop(); XCTAssertFalse(canvas.mouseDownCanMoveWindow)
            drag(canvas, NSPoint(x: 100, y: 60), NSPoint(x: 300, y: 180))
            try assertCrop(canvas.cropSelection, halfCrop)
            XCTAssertEqual(canvas.document, original); XCTAssertEqual(changes, 0); XCTAssertFalse(canvas.canUndo)
            XCTAssertTrue(canvas.applyCrop()); XCTAssertFalse(canvas.isCropping); XCTAssertNil(canvas.cropSelection)
            XCTAssertEqual(changes, 1); XCTAssertEqual(canvas.document.elements, original.elements)
            try assertCrop(canvas.document.crop, halfCrop)
            XCTAssertEqual(canvas.imageFrame, NSRect(x: -200, y: -120, width: 800, height: 480))
            canvas.undoMarkup(); XCTAssertEqual(canvas.document, original); XCTAssertEqual(canvas.imageFrame, canvas.bounds)
            canvas.redoMarkup(); try assertCrop(canvas.document.crop, halfCrop)
            XCTAssertEqual(canvas.document.elements, original.elements); XCTAssertEqual(changes, 3)
        }
    }

    func testApplyingUnchangedFullOrExistingCropSucceedsWithoutPhantomUndo() throws {
        try withCanvas { canvas in
            var changes = 0; canvas.onChange = { changes += 1 }
            canvas.beginCrop(); XCTAssertTrue(canvas.applyCrop()); XCTAssertFalse(canvas.isCropping)
            XCTAssertNil(canvas.document.crop); XCTAssertFalse(canvas.canUndo); XCTAssertEqual(changes, 0)
            let original = ImageMarkupDocument(elements: [mark], crop: halfCrop); canvas.load(original)
            canvas.beginCrop(); XCTAssertTrue(canvas.applyCrop()); XCTAssertFalse(canvas.isCropping)
            XCTAssertEqual(canvas.document, original); XCTAssertFalse(canvas.canUndo); XCTAssertEqual(changes, 0)
        }
    }

    func testCropMoveAndCornerResizeClampToImageAndMinimumSize() throws {
        try withCanvas { canvas in
            canvas.load(.init(crop: halfCrop)); canvas.beginCrop()
            drag(canvas, NSPoint(x: 200, y: 120), NSPoint(x: 1000, y: -400))
            try assertCrop(canvas.cropSelection, .init(x: 0.5, y: 0, width: 0.5, height: 0.5))
            drag(canvas, NSPoint(x: 400, y: 120), NSPoint(x: 150, y: -100))
            let selection = try XCTUnwrap(canvas.cropSelection)
            XCTAssertTrue(selection.width >= 0.0399 && selection.height >= 0.0666)
            XCTAssertTrue(selection.width < 0.1 && selection.height < 0.1)
            XCTAssertTrue(selection.isValid)
            drag(canvas, NSPoint(x: 200, y: 0), NSPoint(x: -500, y: -500))
            let expanded = try XCTUnwrap(canvas.cropSelection)
            XCTAssertEqual(expanded.x, 0); XCTAssertEqual(expanded.y, 0)
            XCTAssertTrue(expanded.isValid)
        }
    }

    func testCancelledCropGestureRestoresDraftAndCancelNeverMutatesDocument() throws {
        try withCanvas { canvas in
            let original = ImageMarkupDocument(elements: [mark], crop: halfCrop); canvas.load(original)
            var changes = 0; canvas.onChange = { changes += 1 }; canvas.beginCrop()
            drag(canvas, NSPoint(x: 200, y: 120), NSPoint(x: 260, y: 150), finish: false)
            XCTAssertFalse(canvas.cropSelection == halfCrop)
            canvas.cancelGesture(); XCTAssertTrue(canvas.isCropping)
            XCTAssertEqual(canvas.cropSelection, halfCrop); XCTAssertEqual(canvas.document, original)
            canvas.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 260, y: 150), canvas: canvas))
            XCTAssertEqual(canvas.cropSelection, halfCrop)
            drag(canvas, NSPoint(x: 20, y: 20), NSPoint(x: 200, y: 140))
            canvas.cancelCrop(); XCTAssertFalse(canvas.isCropping); XCTAssertNil(canvas.cropSelection)
            XCTAssertEqual(canvas.document, original); XCTAssertFalse(canvas.canUndo); XCTAssertEqual(changes, 0)
        }
    }

    func testResetFullSelectionUncropsWithoutClearingAnnotationsAndIsUndoable() throws {
        try withCanvas { canvas in
            let original = ImageMarkupDocument(elements: [mark], crop: halfCrop); canvas.load(original)
            canvas.beginCrop(); canvas.resetCropSelection()
            XCTAssertEqual(canvas.cropSelection, .full); XCTAssertEqual(canvas.document, original)
            XCTAssertTrue(canvas.applyCrop()); XCTAssertNil(canvas.document.crop)
            XCTAssertEqual(canvas.document.elements, original.elements)
            canvas.undoMarkup(); XCTAssertEqual(canvas.document, original)
            canvas.clearMarkup(); XCTAssertTrue(canvas.document.elements.isEmpty)
            XCTAssertEqual(canvas.document.crop, halfCrop)
            canvas.undoMarkup(); XCTAssertEqual(canvas.document, original)
            canvas.beginCrop(); canvas.resetCropSelection(); canvas.cancelCrop()
            XCTAssertEqual(canvas.document, original)
        }
    }

    func testCropSelectionUsesOriginalUnitCoordinatesAtEveryCanvasZoom() throws {
        try withCanvas { canvas in
            for size in [NSSize(width: 400, height: 240), NSSize(width: 1200, height: 720)] {
                canvas.load(.init()); canvas.setFrameSize(size); canvas.beginCrop()
                drag(canvas, NSPoint(x: size.width * 0.2, y: size.height * 0.3),
                     NSPoint(x: size.width * 0.8, y: size.height * 0.7))
                try assertCrop(canvas.cropSelection, .init(x: 0.2, y: 0.3, width: 0.6, height: 0.4))
                XCTAssertTrue(canvas.applyCrop())
                XCTAssertTrue(abs(canvas.imageFrame.width - size.width / 0.6) < 0.000001)
                XCTAssertTrue(abs(canvas.imageFrame.height - size.height / 0.4) < 0.000001)
                canvas.beginCrop(); XCTAssertEqual(canvas.imageFrame, canvas.bounds)
                try assertCrop(canvas.cropSelection, .init(x: 0.2, y: 0.3, width: 0.6, height: 0.4))
                canvas.cancelCrop()
            }
            // Fractional display coordinates reaching the source edge must
            // survive strict stored-document validation without rounding > 1.
            canvas.load(.init()); canvas.setFrameSize(NSSize(width: 704, height: 320)); canvas.beginCrop()
            drag(canvas, NSPoint(x: 72.512, y: 32), NSPoint(x: 704, y: 288))
            XCTAssertTrue(try XCTUnwrap(canvas.cropSelection).isValid)
            XCTAssertTrue(canvas.applyCrop()); _ = try canvas.document.validated()
        }
    }

    func testPostCropDrawingSelectionMovementAndResizeUseOriginalImageCoordinates() throws {
        try withCanvas { canvas in
            canvas.load(.init(crop: halfCrop)); canvas.isMarkupEditing = true; canvas.setTool(.rectangle); canvas.filled = true
            drag(canvas, NSPoint(x: 80, y: 48), NSPoint(x: 240, y: 144))
            let created = try XCTUnwrap(canvas.document.elements.first)
            XCTAssertEqual(created.points, [.init(x: 0.35, y: 0.35), .init(x: 0.55, y: 0.55)])
            canvas.setTool(.select)
            drag(canvas, NSPoint(x: 160, y: 96), NSPoint(x: 200, y: 120))
            let moved = try XCTUnwrap(canvas.selected)
            XCTAssertTrue(abs(moved.points[0].x - 0.4) < 0.000001)
            XCTAssertTrue(abs(moved.points[0].y - 0.4) < 0.000001)
            let movedDocument = canvas.document, corner = moved.bounds(in: canvas.imageFrame).origin
            drag(canvas, corner, NSPoint(x: corner.x - 32, y: corner.y - 24))
            XCTAssertTrue(canvas.document.elements[0].points[0].x < moved.points[0].x)
            XCTAssertTrue(canvas.document.elements[0].points[0].y < moved.points[0].y)
            canvas.undoMarkup(); XCTAssertEqual(canvas.document, movedDocument)
            canvas.undoMarkup(); XCTAssertEqual(canvas.document.elements.first, created)
            XCTAssertEqual(canvas.document.crop, halfCrop)
        }
    }

    func testPostCropTextEditorPositionFontAndSavedPointMatchOriginalCoordinates() throws {
        try withCanvas { canvas in
            canvas.load(.init(crop: halfCrop)); canvas.isMarkupEditing = true; canvas.setTool(.text)
            click(canvas, NSPoint(x: 120, y: 72))
            let editor = try XCTUnwrap(canvas.textEditor), viewport = try XCTUnwrap(editor.enclosingScrollView)
            XCTAssertEqual(viewport.frame.origin, NSPoint(x: 120, y: 72))
            XCTAssertEqual(editor.font?.pointSize, 24)
            editor.string = "Kırpılmış görsel ✓"; canvas.finishTextEditing()
            XCTAssertEqual(canvas.document.elements.first?.points, [.init(x: 0.4, y: 0.4)])
            XCTAssertEqual(canvas.document.crop, halfCrop)
            canvas.beginCrop(); XCTAssertEqual(canvas.document.elements.first?.points, [.init(x: 0.4, y: 0.4)])
            XCTAssertEqual(canvas.imageFrame, canvas.bounds); canvas.cancelCrop()
        }
    }

    func testSpacePanWhileCroppingDoesNotChangeSelectionOrCommitCrop() throws {
        _ = NSApplication.shared
        let scroll = ZoomScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
        scroll.fittedSize = scroll.frame.size
        let canvas = ImageMarkupCanvas(frame: scroll.bounds); canvas.zoomScroll = scroll; scroll.documentView = canvas
        let window = NSWindow(contentRect: scroll.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = scroll; defer { window.close() }
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 8, wheel2: 0, wheel3: 0))
        scroll.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: event))); XCTAssertTrue(scroll.canPan)
        canvas.beginCrop(); let selection = canvas.cropSelection
        scroll.contentView.scroll(to: .zero); canvas.spaceHeld = true
        canvas.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 100, y: 100), canvas: canvas))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 20, y: 20), canvas: canvas))
        XCTAssertTrue(scroll.contentView.bounds.minX > 0)
        canvas.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 20, y: 20), canvas: canvas))
        canvas.cancelGesture(); XCTAssertFalse(canvas.spaceHeld)
        XCTAssertEqual(canvas.cropSelection, selection); XCTAssertTrue(canvas.isCropping)
        XCTAssertNil(canvas.document.crop); XCTAssertFalse(canvas.canUndo)
    }
}
