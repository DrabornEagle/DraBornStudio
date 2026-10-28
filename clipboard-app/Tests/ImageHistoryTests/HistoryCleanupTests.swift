import AppKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class HistoryCleanupTests: HistoryTestCase {
    func testCopyingAnExistingItemAgainAlsoKeepsItOutsideTheConfirmationAtASameClockTime() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date }, moveToTrash: fixtureTrash(f.folder))
        let record = try XCTUnwrap(store.captureText("Synthetic copy latest"))
        let snapshot = try store.unsavedHistorySnapshot()
        try store.markCopied([record.id])
        XCTAssertTrue(try store.clearUnsavedHistory(snapshot).isEmpty)
        XCTAssertNil(try store.item(record.id)?.deletedAt)
    }
    func testAnotherConnectionSavingBeforeCleanupWriterLockKeepsTheRecord() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        var onNextClockRead: (() -> Void)?
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: {
            let action = onNextClockRead; onNextClockRead = nil; action?()
            return f.date
        }, moveToTrash: fixtureTrash(f.folder))
        let record = try XCTUnwrap(store.captureText("Synthetic external writer"))
        let other = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date }, moveToTrash: fixtureTrash(f.folder))
        let snapshot = try store.unsavedHistorySnapshot()
        var externalError: Error?
        onNextClockRead = { do { try other.retain([record.id]) } catch { externalError = error } }
        XCTAssertTrue(try store.clearUnsavedHistory(snapshot).isEmpty)
        XCTAssertNil(externalError)
        let kept = try XCTUnwrap(store.item(record.id))
        XCTAssertNotNil(kept.retainedAt); XCTAssertNil(kept.deletedAt)
        XCTAssertEqual(kept.text, record.text)
    }
    func testCleanupFailureRollsBackEveryRecordAndPublishesNoRevision() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date }, moveToTrash: fixtureTrash(f.folder))
        let first = try XCTUnwrap(store.captureText("Synthetic first"))
        let second = try store.captureLink(try XCTUnwrap(URL(string: "https://example.com/rollback")))
        let snapshot = try store.unsavedHistorySnapshot(), revision = store.revision
        let before = try store.records([first.id, second.id])
        let connection = try LibraryDatabase(url: store.root.appendingPathComponent("library.sqlite"))
        try connection.execute("CREATE TRIGGER synthetic_cleanup_failure BEFORE UPDATE OF deleted ON items WHEN NEW.deleted IS NOT NULL BEGIN SELECT RAISE(ABORT,'Synthetic cleanup write failure'); END")
        XCTAssertThrowsError(try store.clearUnsavedHistory(snapshot))
        XCTAssertEqual(try store.records([first.id, second.id]), before)
        XCTAssertEqual(store.revision, revision)
        try connection.execute("DROP TRIGGER synthetic_cleanup_failure")
        XCTAssertEqual(Set(try store.clearUnsavedHistory(snapshot)), Set([first.id, second.id]))
    }
    private struct Contract: Decodable {
        struct Record: Decodable { let id: String; let kind: LibraryKind; let save: String? }
        struct Scenario: Decodable {
            let id: String; let kind: String; let captured: [String]; let trashed: [String]
            let retainAfterSnapshot: [String]?; let newCopyAfterSnapshot: Bool?; let recopyAfterSnapshot: [String]?; let cancel: Bool?
        }
        let records: [Record]; let scenarios: [Scenario]
    }
    func testSharedHistoryCleanupContractRunsAgainstActualStore() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let contract = try JSONDecoder().decode(Contract.self, from: Data(contentsOf: root.appendingPathComponent("contracts/history-cleanup.json")))
        for scenario in contract.scenarios {
            let f = try SyntheticFixture(); defer { f.cleanup() }
            let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date }, moveToTrash: fixtureTrash(f.folder))
            let folder = try store.createCollection("Retained folder")
            var aliases = [String: UUID](), originals = [URL: Data]()
            for input in contract.records {
                let record: LibraryRecord
                switch input.kind {
                case .text: record = try XCTUnwrap(store.captureText("Synthetic " + input.id))
                case .link: record = try store.captureLink(try XCTUnwrap(URL(string: "https://example.com/" + input.id)))
                case .image:
                    let url = try f.image(owned: false); originals[url] = try Data(contentsOf: url)
                    record = try store.captureImage(url)
                }
                aliases[input.id] = record.id
                switch input.save {
                case "pin": try store.toggleFavorite([record.id])
                case "unpin": try store.toggleFavorite([record.id]); try store.toggleFavorite([record.id])
                case "folder": try store.assign([record.id], to: folder)
                case "tag": try store.addTag("retained-tag", to: [record.id])
                case "trash": try store.trash([record.id])
                default: break
                }
            }
            let kind = LibraryKind(rawValue: scenario.kind)
            let snapshot = try store.unsavedHistorySnapshot(kind: kind), revision = store.revision
            let expected = Set(scenario.captured.compactMap { aliases[$0] })
            XCTAssertEqual(Set(snapshot.ids), expected, scenario.id)
            XCTAssertEqual(try store.unsavedHistoryCount(kind: kind), expected.count, scenario.id)
            XCTAssertEqual(store.revision, revision, "Reading cleanup candidates must not write")
            for name in scenario.retainAfterSnapshot ?? [] { try store.retain([try XCTUnwrap(aliases[name])]) }
            for name in scenario.recopyAfterSnapshot ?? [] {
                let value = try XCTUnwrap(store.item(try XCTUnwrap(aliases[name])))
                if value.kind == .text { XCTAssertEqual(try store.captureText(try XCTUnwrap(value.text))?.id, value.id) }
                else if value.kind == .link { XCTAssertEqual(try store.captureLink(try XCTUnwrap(value.linkURL)).id, value.id) }
            }
            let later = scenario.newCopyAfterSnapshot == true ? try store.captureText("Synthetic later copy") : nil
            let saved = try store.query(LibraryQuery()).map { $0 }
            let beforeCancel = store.revision
            let moved = scenario.cancel == true ? [] : try store.clearUnsavedHistory(snapshot)
            XCTAssertEqual(Set(moved), Set(scenario.trashed.compactMap { aliases[$0] }), scenario.id)
            if scenario.cancel == true { XCTAssertEqual(store.revision, beforeCancel) }
            for value in saved { XCTAssertEqual(try store.item(value.id), value, "Saved records must remain byte-equivalent") }
            if let later { XCTAssertNil(try store.item(later.id)?.deletedAt) }
            for name in scenario.trashed {
                let value = try XCTUnwrap(store.item(try XCTUnwrap(aliases[name])))
                XCTAssertNotNil(value.deletedAt); XCTAssertFalse(value.onShelf)
            }
            for (url, data) in originals { XCTAssertEqual(try Data(contentsOf: url), data) }
            let emptiedRevision = store.revision
            if scenario.cancel != true {
                XCTAssertTrue(try store.clearUnsavedHistory(snapshot).isEmpty)
                XCTAssertEqual(store.revision, emptiedRevision, "An exhausted confirmation must not write or collect later copies")
                if !moved.isEmpty { try store.restore(moved) }
                for id in moved { XCTAssertNil(try store.item(id)?.deletedAt) }
            }
            let reopened = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date }, moveToTrash: fixtureTrash(f.folder))
            for id in moved { XCTAssertEqual(try reopened.item(id), try store.item(id)) }
            XCTAssertEqual(try reopened.collections(for: try XCTUnwrap(aliases["folder-link"])).map(\.id), [folder])
            XCTAssertEqual(try reopened.tags(for: try XCTUnwrap(aliases["tagged-text"])).count, 1)
        }
    }
}
