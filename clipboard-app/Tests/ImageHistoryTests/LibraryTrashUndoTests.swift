import AppKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class LibraryTrashUndoTests: HistoryTestCase {
    private func store(_ fixture: SyntheticFixture) throws -> LibraryStore {
        try LibraryStore(defaults: fixture.defaults, inbox: fixture.inbox,
            now: { fixture.date }, moveToTrash: fixtureTrash(fixture.folder))
    }
    private func fixture() throws -> SyntheticFixture {
        let value = try SyntheticFixture(); value.date = Date(timeIntervalSince1970: 1_700_000_000); return value
    }
    func testMixedBatchRestoresOriginalShelfFlagsContentOrganizationAndFiles() throws {
        let f = try fixture(); defer { f.cleanup() }; let library = try store(f)
        let original = try f.image(owned: false), originalBytes = try Data(contentsOf: original)
        let image = try library.captureImage(original)
        let text = try XCTUnwrap(library.captureText("Synthetic large note\n" + String(repeating: "x", count: 900_000)))
        let link = try library.captureLink(try XCTUnwrap(URL(string: "https://example.com/keyboard-library")))
        let folder = try library.createCollection("Keyboard folder")
        try library.assign([image.id, text.id], to: folder); try library.addTag("keyboard", to: [text.id, link.id])
        try library.update(image.id) { $0.onShelf = false; $0.title = "Saved image" }
        try library.update(text.id) { $0.note = "Synthetic organization note" }
        let ids = [text.id, image.id, link.id], before = try library.records(ids), revision = library.revision
        let managed = try XCTUnwrap(library.item(image.id)?.fileURL), managedBytes = try Data(contentsOf: managed)
        try library.trashUndoably(ids + [text.id, UUID()])
        XCTAssertEqual(library.revision, revision + 1); XCTAssertTrue(library.canUndoTrash)
        for value in try library.records(ids) {
            XCTAssertNotNil(value.deletedAt); XCTAssertNotNil(value.trashRevision); XCTAssertFalse(value.onShelf)
        }
        XCTAssertEqual(try library.undoTrash(), ids)
        XCTAssertEqual(library.revision, revision + 2); XCTAssertFalse(library.canUndoTrash)
        XCTAssertEqual(try library.records(ids), before)
        XCTAssertEqual(try library.collections(for: image.id).map(\.id), [folder])
        XCTAssertEqual(try library.tags(for: text.id).map(\.name), ["keyboard"])
        XCTAssertEqual(try Data(contentsOf: original), originalBytes)
        XCTAssertEqual(try Data(contentsOf: managed), managedBytes)
    }
    func testMissingAndAlreadyTrashedItemsDoNotReplaceThePendingUndoBatch() throws {
        let f = try fixture(); defer { f.cleanup() }; let library = try store(f)
        let old = try XCTUnwrap(library.captureText("Already in Trash")), live = try XCTUnwrap(library.captureText("New user removal"))
        try library.trash([old.id]); let oldTrash = try library.item(old.id), revision = library.revision
        try library.trashUndoably([UUID(), old.id])
        XCTAssertEqual(library.revision, revision); XCTAssertFalse(library.canUndoTrash)
        try library.trashUndoably([live.id, live.id]); let after = library.revision
        try library.trashUndoably([live.id, old.id])
        XCTAssertEqual(library.revision, after); XCTAssertTrue(library.canUndoTrash)
        XCTAssertEqual(try library.undoTrash(), [live.id]); XCTAssertEqual(try library.item(old.id), oldTrash)
        XCTAssertFalse(library.canUndoTrash)
    }
    func testNewestStaleBatchIsSkippedWithoutOverwritingForeignEdits() throws {
        let f = try fixture(); defer { f.cleanup() }; let library = try store(f), other = try store(f)
        let a = try XCTUnwrap(library.captureText("Old batch A")), b = try XCTUnwrap(library.captureText("Old batch B"))
        let c = try XCTUnwrap(library.captureText("Newer edited batch"))
        try library.trashUndoably([a.id, b.id]); try library.trashUndoably([c.id])
        try other.update(c.id) { $0.note = "Edited after removal at an unchanged clock" }
        let changed = try library.item(c.id)
        XCTAssertEqual(try library.undoTrash(), [a.id, b.id]); XCTAssertEqual(try library.item(c.id), changed)
        XCTAssertFalse(library.canUndoTrash)
    }
    func testSameClockForeignRestoreAndRetrashHasANewGeneration() throws {
        let f = try fixture(); defer { f.cleanup() }; let library = try store(f), other = try store(f)
        let value = try XCTUnwrap(library.captureText("Same clock foreign restore and re-trash"))
        try library.trashUndoably([value.id]); let first = try XCTUnwrap(library.item(value.id))
        try other.restore([value.id]); XCTAssertNil(try other.item(value.id)?.trashRevision)
        try other.trash([value.id]); let second = try XCTUnwrap(other.item(value.id))
        XCTAssertEqual(first.deletedAt, second.deletedAt); XCTAssertEqual(first.updatedAt, second.updatedAt)
        XCTAssertNotEqual(first.trashRevision, second.trashRevision)
        XCTAssertTrue(try library.undoTrash().isEmpty); XCTAssertEqual(try library.item(value.id), second)
        XCTAssertFalse(library.canUndoTrash)
    }
    func testOrdinaryRestoreAndTrashInvalidateOlderOwnUndoEvenAtTheSameClock() throws {
        let f = try fixture(); defer { f.cleanup() }; let library = try store(f)
        let value = try XCTUnwrap(library.captureText("Ordinary restore invalidates user undo"))
        try library.trashUndoably([value.id]); XCTAssertTrue(library.canUndoTrash)
        try library.restore([value.id]); XCTAssertFalse(library.canUndoTrash)
        try library.trash([value.id]); let after = try library.item(value.id)
        XCTAssertTrue(try library.undoTrash().isEmpty); XCTAssertEqual(try library.item(value.id), after)
    }
    func testGenericForeignFlagTransitionsAlsoRotateTheTrashGeneration() throws {
        let f = try fixture(); defer { f.cleanup() }; let library = try store(f), other = try store(f)
        let value = try XCTUnwrap(library.captureText("Generic foreign transitions"))
        try library.trashUndoably([value.id]); let initial = try XCTUnwrap(library.item(value.id)?.trashRevision)
        try other.update(value.id) { $0.deletedAt = nil; $0.onShelf = true }
        XCTAssertNil(try other.item(value.id)?.trashRevision)
        try other.update(value.id) { $0.deletedAt = f.date; $0.onShelf = false }
        let changed = try XCTUnwrap(other.item(value.id)); XCTAssertNotNil(changed.trashRevision); XCTAssertNotEqual(changed.trashRevision, initial)
        XCTAssertTrue(try library.undoTrash().isEmpty); XCTAssertEqual(try library.item(value.id), changed)
    }
    func testForeignOrganizationAndColumnChangesAreNotOverwritten() throws {
        let f = try fixture(); defer { f.cleanup() }; let library = try store(f)
        let a = try XCTUnwrap(library.captureText("Membership edit")), b = try XCTUnwrap(library.captureText("Column edit"))
        let folder = try library.createCollection("Added after Trash")
        try library.trashUndoably([a.id, b.id])
        let connection = try LibraryDatabase(url: library.databaseURL)
        try connection.execute("INSERT INTO item_collections(item,collection) VALUES(?,?)", [.text(a.id.uuidString), .text(folder.uuidString)])
        try connection.execute("UPDATE items SET favorite=1 WHERE id=?", [.text(b.id.uuidString)])
        XCTAssertTrue(try library.undoTrash().isEmpty)
        XCTAssertNotNil(try library.item(a.id)?.deletedAt); XCTAssertNotNil(try library.item(b.id)?.deletedAt)
        XCTAssertEqual(try library.collections(for: a.id).map(\.id), [folder])
        XCTAssertEqual(try connection.rows("SELECT favorite FROM items WHERE id=?", [.text(b.id.uuidString)]).first?["favorite"]?.number, 1)
    }
    func testForeignPermanentRemovalIsSkippedWhileTheRemainingBatchRestores() throws {
        let f = try fixture(); defer { f.cleanup() }; let library = try store(f)
        let a = try XCTUnwrap(library.captureText("Permanently removed by another writer")), b = try XCTUnwrap(library.captureText("Still undoable"))
        try library.trashUndoably([a.id, b.id]); let connection = try LibraryDatabase(url: library.databaseURL)
        try connection.execute("DELETE FROM items WHERE id=?", [.text(a.id.uuidString)])
        XCTAssertEqual(try library.undoTrash(), [b.id]); XCTAssertNil(try library.item(a.id))
        XCTAssertNil(try library.item(b.id)?.deletedAt)
    }
    func testTrashFailureRollsBackEveryRowAndKeepsThePreviousUndoBatch() throws {
        let f = try fixture(); defer { f.cleanup() }; let library = try store(f)
        let old = try XCTUnwrap(library.captureText("Previously undoable"))
        let a = try XCTUnwrap(library.captureText("First transactional removal")), b = try XCTUnwrap(library.captureText("Second transactional removal"))
        try library.trashUndoably([old.id]); let before = try library.records([a.id, b.id]), revision = library.revision
        let connection = try LibraryDatabase(url: library.databaseURL)
        try connection.execute("CREATE TRIGGER synthetic_trash_abort BEFORE UPDATE OF deleted ON items WHEN NEW.deleted IS NOT NULL AND NEW.id='\(b.id.uuidString)' BEGIN SELECT RAISE(ABORT,'Synthetic trash failure'); END")
        XCTAssertThrowsError(try library.trashUndoably([a.id, b.id]))
        XCTAssertEqual(try library.records([a.id, b.id]), before); XCTAssertEqual(library.revision, revision)
        XCTAssertTrue(library.canUndoTrash); XCTAssertEqual(try library.undoTrash(), [old.id])
        try connection.execute("DROP TRIGGER synthetic_trash_abort")
        try library.trashUndoably([a.id, b.id]); XCTAssertEqual(try library.undoTrash(), [a.id, b.id])
    }
    func testUndoFailureRollsBackTheWholeBatchAndKeepsItRetryable() throws {
        let f = try fixture(); defer { f.cleanup() }; let library = try store(f)
        let a = try XCTUnwrap(library.captureText("First undo record")), b = try XCTUnwrap(library.captureText("Second undo record"))
        try library.trashUndoably([a.id, b.id]); let before = try library.records([a.id, b.id]), revision = library.revision
        let connection = try LibraryDatabase(url: library.databaseURL)
        try connection.execute("CREATE TRIGGER synthetic_undo_abort BEFORE UPDATE OF deleted ON items WHEN NEW.deleted IS NULL AND NEW.id='\(b.id.uuidString)' BEGIN SELECT RAISE(ABORT,'Synthetic undo failure'); END")
        XCTAssertThrowsError(try library.undoTrash())
        XCTAssertEqual(try library.records([a.id, b.id]), before); XCTAssertEqual(library.revision, revision); XCTAssertTrue(library.canUndoTrash)
        try connection.execute("DROP TRIGGER synthetic_undo_abort")
        XCTAssertEqual(try library.undoTrash(), [a.id, b.id]); XCTAssertFalse(library.canUndoTrash)
    }
    func testTrashAndUndoAcquireTheWriterLockBeforeClockReadsOrRechecks() throws {
        let f = try fixture(); defer { f.cleanup() }; var nextClock: (() -> Void)?
        let library = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { let work = nextClock; nextClock = nil; work?(); return f.date }, moveToTrash: fixtureTrash(f.folder))
        let record = try XCTUnwrap(library.captureText("Writer lock fixture")), connection = try LibraryDatabase(url: library.databaseURL)
        try connection.execute("PRAGMA busy_timeout=1")
        var blocked = 0
        func attemptForeignWrite() {
            do { try connection.execute("UPDATE items SET shelf=0 WHERE id=?", [.text(record.id.uuidString)]) }
            catch { if (error as? LibraryDatabase.Failure)?.code == 5 { blocked += 1 } }
        }
        nextClock = attemptForeignWrite; try library.trashUndoably([record.id]); XCTAssertEqual(blocked, 1)
        nextClock = attemptForeignWrite; XCTAssertEqual(try library.undoTrash(), [record.id]); XCTAssertEqual(blocked, 2)
        XCTAssertTrue(try XCTUnwrap(library.item(record.id)).onShelf)
    }
    func testJournalKeepsTheNewestEightyBatchesAndDoesNotSurviveRestart() throws {
        let f = try fixture(); defer { f.cleanup() }; let library = try store(f)
        var ids = [UUID]()
        for index in 0..<81 {
            let value = try XCTUnwrap(library.captureText("Bounded undo batch \(index)")); ids.append(value.id)
            try library.trashUndoably([value.id])
        }
        let restarted = try store(f); XCTAssertFalse(restarted.canUndoTrash); XCTAssertTrue(try restarted.undoTrash().isEmpty)
        for expected in ids.dropFirst().reversed() { XCTAssertEqual(try library.undoTrash(), [expected]) }
        XCTAssertFalse(library.canUndoTrash); XCTAssertTrue(try library.undoTrash().isEmpty)
        XCTAssertNotNil(try library.item(ids[0])?.deletedAt)
    }
    func testTrashGenerationIsAdditiveAndCleanupAndShelfRemovalRotateIt() throws {
        let f = try fixture(); defer { f.cleanup() }; let library = try store(f)
        let value = try XCTUnwrap(library.captureText("Additive generation fixture"))
        let legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any]
        XCTAssertNil(legacy?["trashRevision"])
        try library.removeFromShelf([value.id]); let removed = try XCTUnwrap(library.item(value.id))
        XCTAssertNotNil(removed.trashRevision); XCTAssertEqual(try library.undoShelfRemoval(), [value.id])
        XCTAssertNil(try library.item(value.id)?.trashRevision)
        let snapshot = try library.unsavedHistorySnapshot(); XCTAssertEqual(try library.clearUnsavedHistory(snapshot), [value.id])
        let cleanup = try XCTUnwrap(library.item(value.id)); XCTAssertNotNil(cleanup.trashRevision); XCTAssertNotEqual(cleanup.trashRevision, removed.trashRevision)
        try library.restore([value.id]); XCTAssertNil(try library.item(value.id)?.trashRevision)
        let db = try LibraryDatabase(url: library.databaseURL)
        XCTAssertEqual(try db.rows("PRAGMA user_version").first?["user_version"]?.number, 1)
    }
}
