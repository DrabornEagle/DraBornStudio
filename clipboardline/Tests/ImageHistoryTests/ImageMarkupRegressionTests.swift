import AppKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class ImageMarkupRegressionTests: HistoryTestCase {
    private func mouse(_ type: NSEvent.EventType, _ point: NSPoint, canvas: ImageMarkupCanvas) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: canvas.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    private func withCanvas(_ body: (ImageMarkupCanvas) throws -> Void) rethrows {
        _ = NSApplication.shared
        let canvas = ImageMarkupCanvas(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
        let window = NSWindow(contentRect: canvas.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas; canvas.isMarkupEditing = true
        defer { window.close() }; try body(canvas)
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
    private func lines(_ editor: NSTextView) throws -> Int {
        let manager = try XCTUnwrap(editor.layoutManager), container = try XCTUnwrap(editor.textContainer)
        manager.ensureLayout(for: container)
        var count = 0
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { _, _, _, _, _ in count += 1 }
        return count
    }
    private var rectangle: ImageMarkupDocument {
        ImageMarkupDocument(elements: [ImageMarkupElement(tool: .rectangle, points: [.init(x: 0.2, y: 0.25), .init(x: 0.6, y: 0.75)], fill: true)])
    }

    func testLongNativeTextNeverSoftWrapsAndCaretScrollsWithinImageEditor() throws {
        try withCanvas { canvas in
            canvas.setTool(.text); click(canvas, NSPoint(x: 40, y: 50))
            let editor = try XCTUnwrap(canvas.textEditor)
            let text = String(repeating: "İstanbul annotation ✓ ", count: 16)
            editor.string = text; editor.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
            canvas.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
            XCTAssertEqual(try lines(editor), 1, "The renderer stores explicit line breaks only")
            let viewport = try XCTUnwrap(editor.enclosingScrollView)
            XCTAssertTrue(viewport.hasHorizontalScroller)
            XCTAssertTrue(editor.frame.width > viewport.contentSize.width)
            XCTAssertTrue(viewport.contentView.bounds.minX > 0, "The native caret should remain reachable in long text")
            XCTAssertTrue(viewport.frame.width <= canvas.bounds.width)
            XCTAssertEqual(canvas.subviews.filter { $0 is NSScrollView }.count, 1)
            canvas.finishTextEditing()
            XCTAssertEqual(canvas.document.elements.first?.text, text)
            XCTAssertFalse(canvas.subviews.contains { $0 is NSScrollView })
        }
    }

    func testExplicitUnicodeNewlinesRemainTwoNativeAndPersistedLines() throws {
        try withCanvas { canvas in
            canvas.setTool(.text); click(canvas, NSPoint(x: 40, y: 50))
            let editor = try XCTUnwrap(canvas.textEditor)
            let text = String(repeating: "İlk satır 🌍 ", count: 12) + "\n" + String(repeating: "İkinci ✓ ", count: 10)
            editor.string = text
            canvas.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
            XCTAssertEqual(try lines(editor), 2)
            canvas.finishTextEditing()
            XCTAssertEqual(canvas.document.elements.first?.text, text)
            canvas.undoMarkup(); XCTAssertTrue(canvas.document.isEmpty)
            canvas.redoMarkup(); XCTAssertEqual(canvas.document.elements.first?.text, text)
        }
    }

    func testFilledShapeSettingDoesNotMakeStrokeToolsSolidOrStealInteriorClicks() throws {
        try withCanvas { canvas in
            canvas.filled = true
            for tool in [ImageMarkupTool.pen, .marker, .arrow, .line] {
                canvas.load(.init()); canvas.setTool(tool)
                drag(canvas, NSPoint(x: 40, y: 24), NSPoint(x: 360, y: 216))
                XCTAssertFalse(try XCTUnwrap(canvas.document.elements.first).fill)
                // Old serialized documents may contain the ignored fill flag.
                // Hit testing must still match the pixels for those documents.
                let legacy = ImageMarkupElement(tool: tool, points: [.init(x: 0.1, y: 0.1), .init(x: 0.9, y: 0.9)], lineWidth: 0.008, fill: true)
                canvas.load(.init(elements: [legacy])); canvas.setTool(.select)
                click(canvas, NSPoint(x: 80, y: 180)); XCTAssertNil(canvas.selectedID)
                click(canvas, NSPoint(x: 200, y: 120)); XCTAssertEqual(canvas.selectedID, legacy.id)
            }
        }
    }

    func testCancelledSelectionMoveRestoresGeometryWithoutPhantomUndo() throws {
        try withCanvas { canvas in
            let original = rectangle
            canvas.load(original); canvas.setTool(.select)
            var changes = 0; canvas.onChange = { changes += 1 }
            drag(canvas, NSPoint(x: 160, y: 120), NSPoint(x: 210, y: 145), finish: false)
            XCTAssertFalse(canvas.document == original)
            canvas.cancelGesture()
            XCTAssertEqual(canvas.document, original); XCTAssertFalse(canvas.canUndo); XCTAssertEqual(changes, 0)
            canvas.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 210, y: 145), canvas: canvas))
            XCTAssertEqual(canvas.document, original); XCTAssertFalse(canvas.canUndo)
            drag(canvas, NSPoint(x: 160, y: 120), NSPoint(x: 200, y: 140))
            XCTAssertFalse(canvas.document == original); XCTAssertEqual(changes, 1)
            canvas.undoMarkup(); XCTAssertEqual(canvas.document, original)
        }
    }

    func testCancelledResizeRestoresGeometryAndLoadingDropsPendingGesture() throws {
        try withCanvas { canvas in
            let original = rectangle
            canvas.load(original); canvas.setTool(.select); click(canvas, NSPoint(x: 160, y: 120))
            let corner = try XCTUnwrap(canvas.selected).bounds(in: canvas.bounds).origin
            drag(canvas, corner, NSPoint(x: corner.x - 25, y: corner.y - 20), finish: false)
            XCTAssertFalse(canvas.document == original)
            canvas.cancelGesture(); XCTAssertEqual(canvas.document, original); XCTAssertFalse(canvas.canUndo)
            drag(canvas, NSPoint(x: 160, y: 120), NSPoint(x: 200, y: 145), finish: false)
            canvas.load(.init())
            canvas.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 200, y: 145), canvas: canvas))
            XCTAssertTrue(canvas.document.isEmpty); XCTAssertFalse(canvas.canUndo); XCTAssertNil(canvas.selectedID)
        }
    }

    func testNativeTextStyleCommitAndZoomPreserveDocumentAndDisposeEditorViewport() throws {
        try withCanvas { canvas in
            canvas.setTool(.text); click(canvas, NSPoint(x: 40, y: 50))
            try XCTUnwrap(canvas.textEditor).string = "Renk ve boyut ✓"
            canvas.applyStyle(color: .blue, fontSize: 0.08)
            XCTAssertFalse(canvas.isTextEditing); XCTAssertFalse(canvas.subviews.contains { $0 is NSScrollView })
            let styled = try XCTUnwrap(canvas.document.elements.first)
            XCTAssertEqual(styled.color, .blue); XCTAssertEqual(styled.fontSize, 0.08)
            canvas.undoMarkup(); XCTAssertEqual(canvas.document.elements.first?.fontSize, 0.05)
            canvas.undoMarkup(); XCTAssertTrue(canvas.document.isEmpty)
            canvas.setTool(.text); click(canvas, NSPoint(x: 40, y: 50))
            try XCTUnwrap(canvas.textEditor).string = "Zoom sırasında korunur 🌍"
            canvas.setFrameSize(NSSize(width: 800, height: 480))
            XCTAssertFalse(canvas.isTextEditing); XCTAssertFalse(canvas.subviews.contains { $0 is NSScrollView })
            XCTAssertEqual(canvas.document.elements.first?.text, "Zoom sırasında korunur 🌍")
            XCTAssertEqual(canvas.document.elements.first?.points, [MarkupPoint(x: 0.1, y: 50.0 / 240)])
            canvas.load(.init()); XCTAssertFalse(canvas.isTextEditing); XCTAssertFalse(canvas.subviews.contains { $0 is NSScrollView })
        }
    }
}
