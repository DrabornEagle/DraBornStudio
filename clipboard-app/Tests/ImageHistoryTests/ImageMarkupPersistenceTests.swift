import AppKit
import ImageIO
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class ImageMarkupPersistenceTests: HistoryTestCase {
    private func store(_ f: SyntheticFixture, trash: ((URL) throws -> URL)? = nil) throws -> LibraryStore {
        try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date }, moveToTrash: trash ?? fixtureTrash(f.folder))
    }
    private func image(_ f: SyntheticFixture, jpeg: Bool = false) throws -> URL {
        let folder = f.folder.appendingPathComponent("Originals")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(jpeg ? "My source.jpg" : "My source.png")
        let context = try XCTUnwrap(CGContext(data: nil, width: 160, height: 100, bitsPerComponent: 8, bytesPerRow: 640,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 160, height: 100))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, (jpeg ? "public.jpeg" : "public.png") as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination)); return url
    }
    private func document(_ color: MarkupColor = .red) -> ImageMarkupDocument {
        ImageMarkupDocument(elements: [ImageMarkupElement(tool: .rectangle,
            points: [MarkupPoint(x: 0.2, y: 0.2), MarkupPoint(x: 0.8, y: 0.8)], color: color, lineWidth: 0.05, fill: true)])
    }
    private func pixels(_ data: Data) throws -> Data {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: try XCTUnwrap(context.data), count: image.width * image.height * 4)
    }
    func testMarkupPreservesExternalOriginalIdentityAndTemporaryRetention() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }; let library = try store(f)
        let original = try image(f), bytes = try Data(contentsOf: original), item = try library.captureImage(original), marks = document()
        let edited = try library.saveImageMarkup(item.id, document: marks)
        XCTAssertEqual(edited.id, item.id); XCTAssertEqual(edited.createdAt, item.createdAt)
        XCTAssertEqual(edited.favorite, item.favorite); XCTAssertNil(edited.retainedAt); XCTAssertTrue(edited.onShelf)
        XCTAssertEqual(edited.originalPath, original.path); XCTAssertEqual(edited.imageMarkup, marks)
        XCTAssertEqual(try Data(contentsOf: original), bytes)
        let base = try XCTUnwrap(edited.markupSourceURL), rendered = try XCTUnwrap(edited.fileURL)
        XCTAssertTrue(library.files.isFavoriteCopy(base)); XCTAssertTrue(library.files.isFavoriteCopy(rendered))
        XCTAssertTrue(base != rendered); XCTAssertEqual(try Data(contentsOf: base), bytes)
        XCTAssertTrue(try pixels(Data(contentsOf: rendered)) != pixels(bytes))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: rendered.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testReopenAndReeditUseImmutableBaseEvenAfterExternalOriginalIsRemoved() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }; let library = try store(f)
        let original = try image(f), initial = try library.captureImage(original), first = try library.saveImageMarkup(initial.id, document: document())
        let base = try XCTUnwrap(first.markupSourceURL)
        try FileManager.default.removeItem(at: original)
        let reopened = try store(f), loaded = try XCTUnwrap(reopened.item(initial.id))
        XCTAssertEqual(loaded.imageMarkup, first.imageMarkup); XCTAssertEqual(loaded.markupSourceURL, base)
        let secondDocument = document(.blue), second = try reopened.saveImageMarkup(initial.id, document: secondDocument)
        XCTAssertEqual(second.markupSourceURL, base); XCTAssertEqual(second.imageMarkup, secondDocument)
        XCTAssertEqual(try pixels(Data(contentsOf: XCTUnwrap(second.fileURL))), try pixels(ImageMarkupRenderer.render(sourceURL: base, document: secondDocument)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(first.path)))
        // If a generated asset disappears, saving the same vectors repairs it
        // from the immutable base rather than treating it as a no-op.
        try FileManager.default.removeItem(at: try XCTUnwrap(second.fileURL))
        let repaired = try reopened.saveImageMarkup(initial.id, document: secondDocument)
        XCTAssertEqual(repaired.markupSourceURL, base); XCTAssertEqual(repaired.imageMarkup, secondDocument)
        XCTAssertEqual(try pixels(Data(contentsOf: XCTUnwrap(repaired.fileURL))), try pixels(ImageMarkupRenderer.render(sourceURL: base, document: secondDocument)))
    }
    func testMarkupPreservesPinFoldersTagsNotesAndShelfAdapterIdentity() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }; let library = try store(f)
        let item = try library.captureImage(try image(f)), folder = try library.createCollection("References")
        try library.assign([item.id], to: folder); try library.addTag("work", to: [item.id]); try library.toggleFavorite([item.id])
        try library.update(item.id) { $0.note = "Notes stay"; $0.title = "Source title" }
        let before = try XCTUnwrap(library.item(item.id)), edited = try library.saveImageMarkup(item.id, document: document())
        XCTAssertEqual(edited.retainedAt, before.retainedAt); XCTAssertEqual(edited.favorite, before.favorite)
        XCTAssertEqual(edited.note, before.note); XCTAssertEqual(edited.title, before.title)
        XCTAssertEqual(try library.collections(for: item.id).map(\.id), [folder]); XCTAssertEqual(try library.tags(for: item.id).map(\.name), ["work"])
        let adapter = ImageHistory(defaults: f.defaults, inbox: f.inbox, library: library)
        XCTAssertEqual(adapter.entries.first?.id, item.id); XCTAssertEqual(adapter.entries.first?.path, edited.path)
        XCTAssertTrue(adapter.entries.first?.pinned == true)
    }
    func testCopyExportAndDragUseFlattenedPNGAndCorrectExtension() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }; let library = try store(f)
        let item = try library.captureImage(try image(f, jpeg: true)), edited = try library.saveImageMarkup(item.id, document: document())
        let rendered = try XCTUnwrap(edited.fileURL), bytes = try Data(contentsOf: rendered)
        let copied = try LibraryTransfer.pasteboardItems([edited])
        XCTAssertEqual(copied.count, 1)
        XCTAssertEqual(try pixels(XCTUnwrap(copied.first?.data(forType: .png))), try pixels(bytes))
        let sources = try LibraryTransfer.exportSources([edited], store: library)
        XCTAssertEqual(sources.first?.url, rendered); XCTAssertEqual(sources.first?.name, "My source.png")
        let destination = f.folder.appendingPathComponent("Exports")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let exports = try library.files.export(sources, to: destination)
        XCTAssertTrue(exports.failed.isEmpty); XCTAssertEqual(try Data(contentsOf: XCTUnwrap(exports.copies.first)), bytes)
        let drag = try LibraryTransfer.dragItems([edited], store: library)
        XCTAssertEqual(drag.first?.sourceURL, rendered)
        let adapter = ImageHistory(defaults: f.defaults, inbox: f.inbox, library: library)
        XCTAssertEqual(adapter.entries.first?.exportFileName, "My source.png")
    }
    func testClearingAllMarksRestoresBaseAndKeepsOriginalRecoverable() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }; var trashed = [URL]()
        let trash = fixtureTrash(f.folder), library = try store(f, trash: { url in trashed.append(url); return try trash(url) })
        let original = try image(f), bytes = try Data(contentsOf: original), item = try library.captureImage(original)
        let edited = try library.saveImageMarkup(item.id, document: document()), base = try XCTUnwrap(edited.markupSourceURL)
        let cleared = try library.saveImageMarkup(item.id, document: ImageMarkupDocument())
        XCTAssertEqual(cleared.id, item.id); XCTAssertEqual(cleared.fileURL, base); XCTAssertNil(cleared.imageMarkup); XCTAssertNil(cleared.markupBasePath)
        XCTAssertEqual(try Data(contentsOf: base), bytes); XCTAssertEqual(try Data(contentsOf: original), bytes)
        XCTAssertEqual(trashed, [try XCTUnwrap(edited.fileURL)])
        let second = try library.saveImageMarkup(item.id, document: document(.green))
        XCTAssertEqual(second.markupSourceURL, base); XCTAssertNil(second.retainedAt)
    }
    func testFailedDocumentRenderAndDatabaseWriteLeavePreviousRecordAndPixelsUntouched() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }; let library = try store(f)
        let original = try image(f), item = try library.captureImage(original), bytes = try Data(contentsOf: original)
        var invalid = document(); invalid.elements[0].points[0].x = .nan
        var rejected = false; do { _ = try library.saveImageMarkup(item.id, document: invalid) } catch { rejected = true }
        XCTAssertTrue(rejected); XCTAssertEqual(try library.item(item.id), item)
        let connection = try LibraryDatabase(url: library.databaseURL)
        try connection.execute("CREATE TRIGGER reject_markup BEFORE UPDATE ON items BEGIN SELECT RAISE(ABORT,'synthetic failure'); END")
        rejected = false; do { _ = try library.saveImageMarkup(item.id, document: document()) } catch { rejected = true }
        XCTAssertTrue(rejected); XCTAssertEqual(try library.item(item.id), item); XCTAssertEqual(try Data(contentsOf: original), bytes)
        XCTAssertEqual(try connection.rows("SELECT count(*) AS n FROM image_markup_garbage").first?["n"]?.number, 0)
        XCTAssertTrue(library.files.files(in: library.files.favoritesFolder, matching: library.files.isFavoriteCopy).isEmpty)
        try connection.execute("DROP TRIGGER reject_markup")
        try Data("Not an image".utf8).write(to: original)
        rejected = false; do { _ = try library.saveImageMarkup(item.id, document: document()) } catch { rejected = true }
        XCTAssertTrue(rejected); XCTAssertEqual(try library.item(item.id), item)
        XCTAssertTrue(library.files.files(in: library.files.favoritesFolder, matching: library.files.isFavoriteCopy).isEmpty)
    }
    func testRetiredRenderCleanupRetriesAfterTrashFailureAndNeverTrashesBase() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let library = try store(f, trash: { _ in throw HistoryFiles.Failure.unsafeFile })
        let item = try library.captureImage(try image(f)), first = try library.saveImageMarkup(item.id, document: document())
        let second = try library.saveImageMarkup(item.id, document: document(.blue))
        let connection = try LibraryDatabase(url: library.databaseURL)
        XCTAssertEqual(try connection.rows("SELECT count(*) AS n FROM image_markup_garbage").first?["n"]?.number, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(first.path)))
        let reopened = try store(f)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(first.path)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(second.path)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(second.markupBasePath)))
        XCTAssertEqual(try reopened.item(item.id), second)
        XCTAssertEqual(try connection.rows("SELECT count(*) AS n FROM image_markup_garbage").first?["n"]?.number, 0)
    }
    func testFailedReeditKeepsExistingVectorsRenderBaseAndCopyPayload() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }; let library = try store(f)
        let item = try library.captureImage(try image(f)), edited = try library.saveImageMarkup(item.id, document: document())
        let render = try XCTUnwrap(edited.fileURL), base = try XCTUnwrap(edited.markupSourceURL)
        let renderedBytes = try Data(contentsOf: render), baseBytes = try Data(contentsOf: base)
        let connection = try LibraryDatabase(url: library.databaseURL)
        try connection.execute("CREATE TRIGGER reject_markup BEFORE UPDATE ON items BEGIN SELECT RAISE(ABORT,'synthetic failure'); END")
        var rejected = false; do { _ = try library.saveImageMarkup(item.id, document: document(.blue)) } catch { rejected = true }
        XCTAssertTrue(rejected); XCTAssertEqual(try library.item(item.id), edited)
        XCTAssertEqual(try Data(contentsOf: render), renderedBytes); XCTAssertEqual(try Data(contentsOf: base), baseBytes)
        XCTAssertEqual(try connection.rows("SELECT count(*) AS n FROM image_markup_garbage").first?["n"]?.number, 0)
        let copied = try LibraryTransfer.pasteboardItems([try XCTUnwrap(library.item(item.id))])
        XCTAssertEqual(try pixels(XCTUnwrap(copied.first?.data(forType: .png))), try pixels(renderedBytes))
        XCTAssertEqual(Set(library.files.files(in: library.files.favoritesFolder, matching: library.files.isFavoriteCopy).map { $0.resolvingSymlinksInPath() }), Set([base, render].map { $0.resolvingSymlinksInPath() }))
    }
    func testInterruptedAssetJournalRecoveryProtectsCurrentAndBaseReferences() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }; let library = try store(f)
        let item = try library.captureImage(try image(f)), edited = try library.saveImageMarkup(item.id, document: document())
        let abandoned = library.files.favoritesFolder.appendingPathComponent("Favorite \(UUID()).png")
        try FileManager.default.copyItem(at: try XCTUnwrap(edited.fileURL), to: abandoned)
        let connection = try LibraryDatabase(url: library.databaseURL)
        for path in [abandoned.path, try XCTUnwrap(edited.path), try XCTUnwrap(edited.markupBasePath)] {
            try connection.execute("INSERT INTO image_markup_garbage VALUES(?)", [.text(path)])
        }
        let reopened = try store(f)
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(edited.path)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(edited.markupBasePath)))
        XCTAssertEqual(try reopened.item(item.id), edited)
    }
    func testMarkupInvalidatesOCRPixelsAndLegacyPayloadsStillDecode() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }; let library = try store(f)
        let item = try library.captureImage(try image(f)), connection = try LibraryDatabase(url: library.databaseURL)
        try connection.execute("INSERT INTO image_analysis VALUES(?,?,?,?,?,?,?)", [.text(item.id.uuidString), .text(try XCTUnwrap(item.path)), .text("old"), .text("v1"), .text("old OCR"), .text("old OCR"), .blob(Data())])
        let edited = try library.saveImageMarkup(item.id, document: document())
        XCTAssertTrue(try connection.rows("SELECT item FROM image_analysis").isEmpty)
        XCTAssertTrue(ImageSearchWorker.fingerprint(try XCTUnwrap(edited.fileURL))?.contains(try XCTUnwrap(edited.path)) == true)
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(LibraryRecord.self, from: data)
        XCTAssertNil(decoded.imageMarkup); XCTAssertNil(decoded.markupBasePath); XCTAssertEqual(decoded.markupSourceURL, item.fileURL)
    }
}
