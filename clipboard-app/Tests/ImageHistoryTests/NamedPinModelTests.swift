import AppKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class NamedPinModelTests: HistoryTestCase {
    private func store(_ f: SyntheticFixture) throws -> LibraryStore {
        try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date }, moveToTrash: fixtureTrash(f.folder))
    }

    func testTextNamePinsWithoutChangingClipboardValueAndSurvivesReopen() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let library = try store(f), body = "synthetic-value-19👋\nsecond line"
        let original = try XCTUnwrap(library.captureText(body))
        let value = try library.nameAndPin(original.id, name: "  Test credential 👩🏽‍💻  \n")
        XCTAssertEqual(value.title, "Test credential 👩🏽‍💻"); XCTAssertTrue(value.favorite)
        XCTAssertEqual(value.text, body); XCTAssertEqual(value.id, original.id)
        XCTAssertEqual(value.createdAt, original.createdAt); XCTAssertNotNil(value.retainedAt)
        let restored = try XCTUnwrap(store(f).item(value.id))
        XCTAssertEqual(restored, value)
        var copied = ""
        let texts = TextHistory(defaults: f.defaults, folder: f.inbox.appendingPathComponent("Texts"), copyText: { copied = $0 }, library: library)
        XCTAssertEqual(texts.entries.first?.title, value.title)
        texts.copy(value.id); XCTAssertEqual(copied, body)
        XCTAssertEqual(try String(contentsOf: texts.materialize(texts.entries[0]), encoding: .utf8), body)
    }

    func testRenamingAlreadyPinnedNeverUnpinsOrResetsRetentionAndOrganization() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let library = try store(f), original = try XCTUnwrap(library.captureText("Unchanged body"))
        let folder = try library.createCollection("References")
        try library.assign([original.id], to: folder); try library.addTag("draft", to: [original.id])
        try library.update(original.id) { $0.note = "Unchanged note"; $0.lastCopiedAt = f.date }
        let pinned = try library.nameAndPin(original.id, name: "First label")
        f.date.addTimeInterval(90 * 86400)
        let renamed = try library.nameAndPin(original.id, name: "Second label")
        try library.prune()
        XCTAssertTrue(renamed.favorite); XCTAssertEqual(renamed.retainedAt, pinned.retainedAt)
        XCTAssertEqual(renamed.text, "Unchanged body"); XCTAssertEqual(renamed.note, "Unchanged note")
        XCTAssertEqual(renamed.lastCopiedAt, pinned.lastCopiedAt)
        XCTAssertEqual(renamed.updatedAt, f.date)
        XCTAssertEqual(try library.collections(for: original.id).map(\.id), [folder])
        XCTAssertEqual(try library.tags(for: original.id).map(\.name), ["draft"])
        XCTAssertNil(try library.item(original.id)?.deletedAt)
    }

    func testExternalImageNameCreatesManagedCopyAndAdapterCarriesLabel() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let library = try store(f), source = try f.image(owned: false, name: "Capture reference overview.png")
        let bytes = try Data(contentsOf: source), original = try library.captureImage(source)
        let value = try library.nameAndPin(original.id, name: "Screenshot of settings")
        let copy = try XCTUnwrap(value.fileURL)
        XCTAssertTrue(library.files.isFavoriteCopy(copy)); XCTAssertTrue(copy != source)
        XCTAssertEqual(value.originalPath, source.path); XCTAssertEqual(value.id, original.id)
        XCTAssertEqual(try Data(contentsOf: source), bytes); XCTAssertEqual(try Data(contentsOf: copy), bytes)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: copy.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let history = ImageHistory(defaults: f.defaults, inbox: f.inbox, library: library)
        XCTAssertEqual(history.entries.first?.title, value.title)
        let renamed = try library.nameAndPin(original.id, name: "Second screenshot name")
        XCTAssertEqual(renamed.path, copy.path); XCTAssertEqual(renamed.originalPath, source.path)
        XCTAssertEqual(history.entries.first?.title, renamed.title)
        XCTAssertEqual(try store(f).item(original.id)?.title, renamed.title)
        for search in [source.lastPathComponent, "Capture reference", "Second screenshot name"] {
            XCTAssertEqual(try library.query(LibraryQuery(scope: .shelf, search: search)).map(\.id), [original.id])
        }
        XCTAssertTrue(try library.query(LibraryQuery(scope: .shelf, search: source.deletingLastPathComponent().lastPathComponent)).isEmpty)
    }

    func testLinkCustomNamePreservesMetadataAndSearchesBothNamesAndOriginalURL() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let library = try store(f), url = try XCTUnwrap(URL(string: "https://example.com/reference/article?part=2"))
        let original = try library.captureLink(url)
        try library.update(original.id) {
            $0.metadataTitle = "Original video title"; $0.author = "Synthetic author"
            $0.metadataState = "ready"; $0.thumbnailPath = "/synthetic/thumbnail.png"
        }
        let value = try library.nameAndPin(original.id, name: "İş referansı 中文")
        XCTAssertEqual(value.displayTitle, "İş referansı 中文")
        XCTAssertEqual(value.metadataTitle, "Original video title")
        XCTAssertEqual(value.originalURL, url.absoluteString); XCTAssertEqual(value.normalizedURL, original.normalizedURL)
        XCTAssertEqual(value.author, "Synthetic author"); XCTAssertEqual(value.thumbnailPath, "/synthetic/thumbnail.png")
        for search in ["iş referansı", "中文", "Original video", "article?part=2"] {
            XCTAssertEqual(try library.query(LibraryQuery(search: search)).map(\.id), [original.id])
        }
        try library.update(original.id) { $0.metadataTitle = "Refreshed fetched title" }
        XCTAssertEqual(try library.item(original.id)?.displayTitle, value.title)
        XCTAssertEqual(try library.query(LibraryQuery(search: "Refreshed fetched")).map(\.id), [original.id])
    }

    func testTextNameAndBodyBothRemainSearchableThroughShelfQuery() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let library = try store(f), record = try XCTUnwrap(library.captureText("Unrecognizable-value-297"))
        try library.nameAndPin(record.id, name: "Friendly service name")
        for search in ["Friendly service", "Unrecognizable-value-297", "Friendly 297"] {
            XCTAssertEqual(try library.query(LibraryQuery(scope: .shelf, search: search)).map(\.id), [record.id])
        }
    }

    func testInvalidNamesMissingOrDeletedTargetsNeverChangeRowOrRevision() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let library = try store(f), record = try XCTUnwrap(library.captureText("Unchanged"))
        let revision = library.revision
        for name in ["", " \n\t ", "Two\nlines", "Nul\0name", "Line\u{2028}separator", String(repeating: "a", count: 161), "a" + String(repeating: "\u{301}", count: 600)] {
            XCTAssertThrowsError(try library.nameAndPin(record.id, name: name))
            XCTAssertEqual(try library.item(record.id), record); XCTAssertEqual(library.revision, revision)
        }
        XCTAssertThrowsError(try library.nameAndPin(UUID(), name: "Missing"))
        XCTAssertEqual(library.revision, revision)
        try library.trash([record.id]); let deleted = try library.item(record.id), afterTrash = library.revision
        XCTAssertThrowsError(try library.nameAndPin(record.id, name: "Deleted"))
        XCTAssertEqual(try library.item(record.id), deleted); XCTAssertEqual(library.revision, afterTrash)
    }

    func testUnicodeAndExactNameLimitAreAccepted() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let library = try store(f), record = try XCTUnwrap(library.captureText("Body"))
        let limit = String(repeating: "ç", count: LibraryStore.maximumItemNameLength)
        XCTAssertEqual(try library.nameAndPin(record.id, name: limit).title, limit)
        let combined = "Aile 👨‍👩‍👧‍👦 · İŞ · 中文 · e\u{301}"
        XCTAssertEqual(try library.nameAndPin(record.id, name: combined).title, combined)
    }

    func testMissingImageCannotPublishNameOrPin() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let library = try store(f), source = try f.image(owned: false), record = try library.captureImage(source)
        try FileManager.default.moveItem(at: source, to: source.appendingPathExtension("moved"))
        let revision = library.revision
        XCTAssertThrowsError(try library.nameAndPin(record.id, name: "Cannot protect image"))
        XCTAssertEqual(try library.item(record.id), record); XCTAssertEqual(library.revision, revision)
    }

    func testDatabaseFailureLeavesImageRecordUnchangedAndRecoversUnpublishedCopy() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let library = try store(f), source = try f.image(owned: false), record = try library.captureImage(source)
        let bytes = try Data(contentsOf: source), revision = library.revision
        let database = try LibraryDatabase(url: library.databaseURL)
        try database.execute("CREATE TRIGGER reject_named_update BEFORE UPDATE ON items WHEN NEW.favorite=1 BEGIN SELECT RAISE(ABORT,'synthetic write failure'); END")
        XCTAssertThrowsError(try library.nameAndPin(record.id, name: "Rejected image name"))
        XCTAssertEqual(try library.item(record.id), record); XCTAssertEqual(library.revision, revision)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertTrue(library.files.files(in: library.files.favoritesFolder, matching: library.files.isFavoriteCopy).isEmpty)
        let trash = f.folder.appendingPathComponent(".test-trash")
        let recovered = try FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)
        XCTAssertEqual(recovered.count, 1); XCTAssertEqual(try Data(contentsOf: XCTUnwrap(recovered.first)), bytes)
    }

    func testOldHistoryJSONDecodesWithoutNameAndNewNameRoundTrips() throws {
        let id = UUID(), date = Date(timeIntervalSinceReferenceDate: 100)
        let textJSON = try JSONSerialization.data(withJSONObject: ["id": id.uuidString, "text": "original", "capturedAt": 100, "pinned": false])
        let oldText = try JSONDecoder().decode(TextHistory.Entry.self, from: textJSON)
        XCTAssertNil(oldText.title); XCTAssertEqual(oldText.text, "original")
        var namedText = oldText; namedText.title = "Text name"
        XCTAssertEqual(try JSONDecoder().decode(TextHistory.Entry.self, from: JSONEncoder().encode(namedText)), namedText)
        let imageJSON = try JSONSerialization.data(withJSONObject: ["path": "/synthetic/image.png", "capturedAt": 100])
        let oldImage = try JSONDecoder().decode(ImageHistory.Entry.self, from: imageJSON)
        XCTAssertNil(oldImage.title); XCTAssertEqual(oldImage.capturedAt, date)
        let namedImage = ImageHistory.Entry(path: oldImage.path, capturedAt: date, pinned: true, id: id, title: "Image name")
        XCTAssertEqual(try JSONDecoder().decode(ImageHistory.Entry.self, from: JSONEncoder().encode(namedImage)), namedImage)
    }

    func testLegacyMigrationKeepsOptionalNamesSeparateFromContent() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let image = ImageHistory.Entry(path: try f.image().path, capturedAt: f.date, pinned: true, title: "Named legacy screenshot")
        f.defaults.set(try JSONEncoder().encode([image]), forKey: "imageHistoryV1")
        let text = TextHistory.Entry(id: UUID(), text: "Exact legacy body", capturedAt: f.date, pinned: true, title: "Named legacy text")
        let folder = f.inbox.appendingPathComponent("Texts")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode([text]).write(to: folder.appendingPathComponent("history.json"))
        let library = try store(f)
        XCTAssertEqual(try library.item(image.id)?.title, image.title)
        XCTAssertEqual(try library.item(text.id)?.title, text.title)
        XCTAssertEqual(try library.item(text.id)?.text, text.text)
    }
}
