import AppKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor
private final class SyntheticTextClipboard: ClipboardSource {
    var count = 9000
    var values: [[NSPasteboard.PasteboardType: Data]] = []
    var countReads = 0, typeReads = 0, dataReads = 0
    var duringRead: (() -> Void)?
    var changeCount: Int { countReads += 1; return count }
    var itemTypes: [[NSPasteboard.PasteboardType]] { typeReads += 1; return values.map { Array($0.keys) } }
    func data(forType type: NSPasteboard.PasteboardType, at index: Int) -> Data? {
        dataReads += 1; let value = values[index][type]; duringRead?(); return value
    }
    func copy(_ values: [[NSPasteboard.PasteboardType: Data]]) { self.values = values; count += 1 }
}
final class TextAndZoomTests: HistoryTestCase {
    @MainActor private func fixture(_ body: (SyntheticFixture) throws -> Void) throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }; try body(f)
    }
    @MainActor func testDisabledAndEnablingTextWatcherNeverImportsOldClipboard() throws {
        let source = SyntheticTextClipboard(); var received: [String] = []
        let watcher = TextClipboardWatcher(source: source) { received.append($0) }; defer { watcher.stop() }
        source.copy([[.string: Data("old synthetic text".utf8)]])
        watcher.check(); XCTAssertEqual(source.countReads, 0); XCTAssertEqual(source.typeReads, 0)
        watcher.start(); watcher.check(); XCTAssertTrue(received.isEmpty); XCTAssertEqual(source.dataReads, 0)
        source.copy([[.string: Data("fresh synthetic text".utf8)]]); watcher.check(); watcher.check()
        XCTAssertEqual(received.count, 1); XCTAssertEqual(source.dataReads, 1)
        watcher.stop(); source.copy([[.string: Data("while stopped".utf8)]]); watcher.start(); watcher.check()
        XCTAssertEqual(received.count, 1)
    }
    @MainActor func testUnicodeMultilineLongTextRoundTripsAndDoesNotChangeClipboard() throws {
        try fixture { f in
            let source = SyntheticTextClipboard(), texts = f.texts()
            let watcher = TextClipboardWatcher(source: source) { texts.add($0) }; defer { watcher.stop() }
            let value = String(repeating: "İstanbul 👨‍👩‍👧‍👦 中文\nsecond line\n", count: 2000)
            watcher.start(); source.copy([[.string: Data(value.utf8), .rtf: Data("rich format is ignored".utf8)]])
            let before = source.values, count = source.count; watcher.check()
            XCTAssertEqual(texts.entries.first?.text, value); XCTAssertEqual(f.texts().entries.first?.text, value)
            XCTAssertEqual(source.values, before); XCTAssertEqual(source.count, count); XCTAssertEqual(source.dataReads, 1)
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: texts.archive.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: texts.folder.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        }
    }
    @MainActor func testPrivateMarkersImageCompanionsAndFileCopiesAreSkippedBeforeReadingText() throws {
        let source = SyntheticTextClipboard(); var received = 0
        let watcher = TextClipboardWatcher(source: source) { _ in received += 1 }; defer { watcher.stop() }; watcher.start()
        for marker in ClipboardWatcher.privateTypes {
            source.copy([[.string: Data("private synthetic".utf8)], [marker: Data()]])
            watcher.check()
        }
        for marker in [NSPasteboard.PasteboardType.png, .tiff, .fileURL, NSPasteboard.PasteboardType("public.jpeg")] {
            source.copy([[.string: Data("companion".utf8), marker: Data()]]); watcher.check()
        }
        XCTAssertEqual(received, 0); XCTAssertEqual(source.dataReads, 0)
    }
    @MainActor func testOwnTextCopiesEmptyOversizedAndChangingClipboardAreSkipped() throws {
        let savedCount = ClipboardWatcher.ownChangeCount; defer { ClipboardWatcher.recordOwnCopy(changeCount: savedCount) }
        let source = SyntheticTextClipboard(); var received = 0
        let watcher = TextClipboardWatcher(source: source) { _ in received += 1 }; defer { watcher.stop() }; watcher.start()
        source.copy([[.string: Data("own".utf8)]]); ClipboardWatcher.recordOwnCopy(changeCount: source.count); watcher.check()
        XCTAssertEqual(source.typeReads, 0)
        for data in [Data(), Data([0xFF]), Data(repeating: 65, count: TextClipboardWatcher.maximumDataBytes + 1)] {
            source.copy([[.string: data]]); watcher.check()
        }
        source.copy([[.string: Data("raced".utf8)], [.string: Data("other".utf8)]])
        source.duringRead = { source.count += 1 }; let reads = source.dataReads; watcher.check()
        XCTAssertEqual(source.dataReads, reads + 1); XCTAssertEqual(received, 0)
    }
    @MainActor func testTextRetentionPinFavoritesAndRestartUseSharedDuration() throws {
        try fixture { f in
            let texts = f.texts(); XCTAssertTrue(texts.add("pinned synthetic")); let pin = texts.entries[0].id; texts.togglePin(pin)
            f.date.addTimeInterval(1); XCTAssertTrue(texts.add("ordinary synthetic"))
            XCTAssertTrue(texts.add("ordinary synthetic")); XCTAssertEqual(texts.entries.count, 2)
            for days in ImageHistory.dayChoices {
                f.defaults.set(days, forKey: "historyRetentionDays"); XCTAssertEqual(texts.retentionDays, days)
            }
            f.date.addTimeInterval(31 * 86400); texts.prune(); XCTAssertEqual(texts.entries.map(\.id), [pin])
            let restart = f.texts(); XCTAssertEqual(restart.entries, texts.entries)
            restart.setFavoritesOnly(true); XCTAssertEqual(restart.displayEntries.count, 1)
            restart.togglePin(pin); XCTAssertTrue(restart.displayEntries.isEmpty)
            restart.prune(); XCTAssertTrue(restart.entries.isEmpty)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.folder.appendingPathComponent(".test-trash").path).count, 2)
        }
    }
    @MainActor func testTextTrashFailureRetriesWithoutLosingArchive() throws {
        try fixture { f in
            var fail = true
            let texts = TextHistory(defaults: f.defaults, folder: f.inbox.appendingPathComponent("Texts"), now: { f.date }, moveToTrash: { url in
                if fail { throw HistoryFiles.Failure.unsafeFile }; return try fixtureTrash(f.folder)(url)
            })
            texts.add("synthetic retry"); let id = texts.entries[0].id
            texts.trash([id]); XCTAssertEqual(texts.entries.count, 1); XCTAssertEqual(f.texts().entries.count, 1)
            fail = false; texts.trash([id]); XCTAssertTrue(texts.entries.isEmpty); XCTAssertTrue(f.texts().entries.isEmpty)
        }
    }
    @MainActor func testCorruptTextArchiveAndSymlinkArePreserved() throws {
        try fixture { f in
            let texts = f.texts(); texts.add("synthetic before corruption")
            let corrupt = Data("not JSON".utf8); try corrupt.write(to: texts.archive)
            let restored = f.texts(); XCTAssertFalse(restored.add("must not overwrite"))
            XCTAssertEqual(try Data(contentsOf: texts.archive), corrupt)
            try FileManager.default.removeItem(at: texts.archive)
            let original = f.folder.appendingPathComponent("private-test-original.txt"); let bytes = Data("synthetic marker".utf8); try bytes.write(to: original)
            try FileManager.default.createSymbolicLink(at: texts.archive, withDestinationURL: original)
            let linked = f.texts(); XCTAssertFalse(linked.add("ignored")); XCTAssertEqual(try Data(contentsOf: original), bytes)
        }
    }
    @MainActor func testTextKeyboardAndWheelDoNotChangeImageScrollOrTriggerImageActions() throws {
        try fixture { f in
            let line = f.line(); line.setViewportWidth(350); line.hang(try f.image(), quietly: true)
            for i in 0..<20 { line.texts.add("synthetic text \(i)") }
            line.showingTexts = true; var imageActions = 0; var textCopied: UUID?, textPreviewed: UUID?
            let keyboard = LineKeyboard(line: line, onCopy: { _ in imageActions += 1 }, onPreview: { _ in imageActions += 1 },
                onClose: {}, onTextCopy: { textCopied = $0 }, onTextPreview: { textPreviewed = $0 })
            for _ in 0..<8 { _ = keyboard.handle(key(124)) }
            _ = keyboard.handle(key(36)); _ = keyboard.handle(key(49))
            XCTAssertEqual(textCopied, line.texts.focusedID); XCTAssertEqual(textPreviewed, line.texts.focusedID)
            XCTAssertEqual(imageActions, 0); XCTAssertEqual(line.scrollOffset, 0); XCTAssertTrue(line.texts.scrollOffset > 0)
            line.texts.scroll(-100000, width: 350); XCTAssertEqual(line.texts.scrollOffset, Layout.maximumOffset(count: 20, width: 350))
            line.texts.scroll(100000, width: 350); XCTAssertEqual(line.texts.scrollOffset, 0)
            line.texts.scroll(.nan, width: 350); XCTAssertEqual(line.texts.scrollOffset, 0)
        }
    }
    @MainActor func testZoomBoundsResetAndInvalidDeltas() throws {
        var zoom = PreviewZoom(); XCTAssertEqual(zoom.scale, 1)
        zoom.wheel(10000, precise: false); XCTAssertEqual(zoom.scale, 4)
        zoom.wheel(-10000, precise: false); XCTAssertEqual(zoom.scale, 1)
        zoom.wheel(.nan, precise: true); zoom.wheel(.infinity, precise: false); XCTAssertEqual(zoom.scale, 1)
        zoom.reset(); XCTAssertEqual(zoom.scale, 1)
        zoom.wheel(2, precise: true); XCTAssertTrue(zoom.scale > 1); XCTAssertTrue(zoom.scale < 4)
        zoom.reset(); zoom.magnify(1); XCTAssertEqual(zoom.scale, 2)
        zoom.magnify(.nan); XCTAssertEqual(zoom.scale, 2)
        zoom.magnify(100); XCTAssertEqual(zoom.scale, 4)
        zoom.magnify(-100); XCTAssertEqual(zoom.scale, 1)
    }
    @MainActor func testZoomedImageMouseDragPansBothAxesAndClampsWithoutMovingWindow() throws {
        _ = NSApplication.shared
        try fixture { f in
            let url = try f.image()
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 400, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
            let preview = try XCTUnwrap(ImagePreview(url: url))
            defer { preview.window.close() }
            let scroll = preview.scroll, view = try XCTUnwrap(scroll.documentView)
            XCTAssertFalse(scroll.beginPan(at: .zero))
            let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 8, wheel2: 0, wheel3: 0))
            scroll.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: cg)))
            XCTAssertTrue(scroll.canPan); XCTAssertFalse(view.mouseDownCanMoveWindow)
            scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
            let frame = preview.window.frame, before = scroll.contentView.bounds.origin
            @MainActor func mouse(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: preview.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            view.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 20, y: 20)))
            view.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: -80, y: -80)))
            XCTAssertTrue(abs(scroll.contentView.bounds.minX - 100) < 0.01)
            XCTAssertTrue(abs(scroll.contentView.bounds.minY - 100) < 0.01)
            view.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: -5000, y: -5000)))
            let maximum = scroll.contentView.bounds.origin
            XCTAssertTrue(maximum.x > before.x); XCTAssertTrue(maximum.y > before.y)
            XCTAssertTrue(abs(maximum.x - (view.frame.width - scroll.contentView.bounds.width)) < 0.01)
            XCTAssertTrue(abs(maximum.y - (view.frame.height - scroll.contentView.bounds.height)) < 0.01)
            view.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 5000, y: 5000)))
            XCTAssertEqual(scroll.contentView.bounds.origin, .zero)
            view.mouseUp(with: mouse(.leftMouseUp, .zero)); scroll.pan(to: NSPoint(x: -400, y: -400))
            XCTAssertEqual(scroll.contentView.bounds.origin, .zero); XCTAssertEqual(preview.window.frame, frame)
            scroll.resetZoom(); XCTAssertFalse(scroll.canPan); XCTAssertEqual(scroll.zoom.scale, 1)
        }
    }
    @MainActor func testPreviewWheelZoomAndResetStayLocal() throws {
        _ = NSApplication.shared
        let scroll = ZoomScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 180))
        scroll.fittedSize = NSSize(width: 300, height: 180); scroll.documentView = NSImageView(frame: scroll.bounds)
        let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 5, wheel2: 0, wheel3: 0))
        scroll.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: cg)))
        XCTAssertTrue(scroll.zoom.scale > 1); XCTAssertTrue(scroll.documentView!.frame.width > 300)
        scroll.resetZoom(); XCTAssertEqual(scroll.zoom.scale, 1); XCTAssertEqual(scroll.documentView!.frame.width, 300)
        let horizontal = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 0, wheel2: -5, wheel3: 0))
        scroll.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: horizontal))); XCTAssertEqual(scroll.zoom.scale, 1)
    }
    @MainActor private func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }
}
