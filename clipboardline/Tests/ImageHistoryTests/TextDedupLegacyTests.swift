import AppKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class TextDedupLegacyTests: HistoryTestCase {
    private func seeded(_ values: [TextHistory.Entry], fixture f: SyntheticFixture,
                        trash: @escaping (URL) throws -> URL = { $0 }) throws -> TextHistory {
        let folder = f.inbox.appendingPathComponent("Texts")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(values).write(to: folder.appendingPathComponent("history.json"))
        return TextHistory(defaults: f.defaults, folder: folder, now: { f.date },
                           moveToTrash: trash, pruneOnLoad: false)
    }

    func testRecopyMovesExistingStableRecordToFrontAndPersistsNewestCapture() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let texts = f.texts()
        XCTAssertTrue(texts.add("Synthetic A")); let first = try XCTUnwrap(texts.entries.first)
        f.date.addTimeInterval(1)
        XCTAssertTrue(texts.add("Synthetic B")); let other = try XCTUnwrap(texts.entries.first)
        texts.select(first.id, width: 350); texts.scrollOffset = 23
        f.date.addTimeInterval(1)
        XCTAssertTrue(texts.add("Synthetic A"))
        XCTAssertEqual(texts.entries.map(\.id), [first.id, other.id])
        XCTAssertEqual(texts.entries.first?.capturedAt, f.date)
        XCTAssertEqual(texts.entries.last, other)
        XCTAssertEqual(texts.focusedID, first.id)
        XCTAssertEqual(texts.selectedIDs, [first.id])
        XCTAssertEqual(texts.scrollOffset, 0)
        XCTAssertEqual(f.texts().entries, texts.entries)
    }

    func testRecopyAtFrontStillRefreshesTimestampAndSucceeds() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let texts = f.texts()
        XCTAssertTrue(texts.add("Same synthetic value")); let id = try XCTUnwrap(texts.entries.first?.id)
        f.date.addTimeInterval(90)
        XCTAssertTrue(texts.add("Same synthetic value"))
        XCTAssertEqual(texts.entries.count, 1)
        XCTAssertEqual(texts.entries.first?.id, id)
        XCTAssertEqual(texts.entries.first?.capturedAt, f.date)
        // A fresh clipboard event can arrive inside the same clock tick too.
        XCTAssertTrue(texts.add("Same synthetic value"))
        XCTAssertEqual(texts.entries.count, 1)
        XCTAssertEqual(f.texts().entries, texts.entries)
    }

    func testRecopyNormalizesEquivalentTextButPreservesWhitespaceCaseAndInvisibleDifferences() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let texts = f.texts()
        XCTAssertTrue(texts.add("Restoran Listesi Çıkart"))
        let originalID = try XCTUnwrap(texts.entries.first?.id)
        f.date.addTimeInterval(1); XCTAssertTrue(texts.add("Different text"))
        f.date.addTimeInterval(1); XCTAssertTrue(texts.add("Restoran Listesi Çıkart\n"))
        XCTAssertEqual(texts.entries.count, 2)
        XCTAssertEqual(texts.entries.first?.id, originalID)
        for (first, repeated) in [("café\nsecond line", "\r\ncafe\u{301}\r\nsecond line\r\n"),
                                  ("\n", "\r\n"), ("\n\n", "\r\n\r\n")] {
            f.date.addTimeInterval(1); XCTAssertTrue(texts.add(first))
            let id = try XCTUnwrap(texts.entries.first?.id), count = texts.entries.count
            f.date.addTimeInterval(1); XCTAssertTrue(texts.add(repeated))
            XCTAssertEqual(texts.entries.first?.id, id)
            XCTAssertEqual(texts.entries.count, count)
            XCTAssertEqual(Data(try XCTUnwrap(texts.entries.first?.text).utf8), Data(repeated.utf8))
        }
        XCTAssertEqual(texts.entries.count, 5)
        let distinct = ["hello", " hello", "hello ", "Hello", "\thello", "hello\t", "hello\u{200B}",
                        "hello\u{2028}", "first\nsecond", "first\n\nsecond"]
        let count = texts.entries.count
        var ids = Set<UUID>()
        for value in distinct {
            f.date.addTimeInterval(1); XCTAssertTrue(texts.add(value))
            ids.insert(try XCTUnwrap(texts.entries.first?.id))
        }
        XCTAssertEqual(ids.count, distinct.count)
        XCTAssertEqual(texts.entries.count, count + distinct.count)
        XCTAssertEqual(f.texts().entries.map { Data($0.text.utf8) }, texts.entries.map { Data($0.text.utf8) })
    }

    func testNormalizedRecopyRefreshesMaterializedFileAndPreservesNamedPin() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let entry = TextHistory.Entry(id: UUID(), text: "café", capturedAt: f.date, pinned: true, title: "Friendly label")
        let texts = try seeded([entry], fixture: f)
        let file = try texts.materialize(entry)
        for value in ["cafe\u{301}", "\ncafé\r\n"] {
            f.date.addTimeInterval(1)
            XCTAssertTrue(texts.add(value))
            let current = try XCTUnwrap(texts.entries.first)
            XCTAssertEqual(current.id, entry.id)
            XCTAssertEqual(current.title, entry.title)
            XCTAssertTrue(current.pinned)
            XCTAssertEqual(Data(current.text.utf8), Data(value.utf8))
            XCTAssertEqual(try Data(contentsOf: file), Data(value.utf8))
            XCTAssertEqual(try texts.materialize(current), file)
            XCTAssertEqual(f.texts().entries.map { Data($0.text.utf8) }, [Data(value.utf8)])
        }
    }

    func testNormalizedRecopyRejectsUnsafeFilesAndRestoresFileAfterArchiveFailure() throws {
        for failure in ["tamper", "symlink", "archive"] {
            let f = try SyntheticFixture(); defer { f.cleanup() }
            let texts = f.texts()
            XCTAssertTrue(texts.add("Materialized original"))
            let original = try XCTUnwrap(texts.entries.first)
            let file = try texts.materialize(original)
            let archiveBytes = try Data(contentsOf: texts.archive)
            var expected = Data(original.text.utf8)
            if failure == "tamper" {
                expected = Data("Externally modified file".utf8); try expected.write(to: file)
            } else if failure == "symlink" {
                let target = f.folder.appendingPathComponent("outside.txt")
                try expected.write(to: target); try FileManager.default.removeItem(at: file)
                try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
            } else {
                let backup = texts.folder.appendingPathComponent("preserved-history.json")
                try FileManager.default.moveItem(at: texts.archive, to: backup)
                try FileManager.default.createSymbolicLink(at: texts.archive, withDestinationURL: backup)
            }
            texts.select(original.id, width: 350); texts.scrollOffset = 19
            f.date.addTimeInterval(1)
            XCTAssertFalse(texts.add("Materialized original\n"))
            XCTAssertEqual(texts.entries.map(\.id), [original.id])
            XCTAssertEqual(Data(try XCTUnwrap(texts.entries.first?.text).utf8), Data(original.text.utf8))
            XCTAssertEqual(texts.focusedID, original.id)
            XCTAssertEqual(texts.selectedIDs, [original.id])
            XCTAssertEqual(texts.scrollOffset, 19)
            XCTAssertEqual(try Data(contentsOf: texts.archive), archiveBytes)
            XCTAssertEqual(try Data(contentsOf: file), expected)
            if failure == "symlink" { XCTAssertTrue(try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true) }
        }
    }

    func testRecopyPreservesPinnedNameAndLeavesMaterializedFilesAlone() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let entry = TextHistory.Entry(id: UUID(), text: "synthetic-opaque-value", capturedAt: f.date,
                                      pinned: true, title: "Useful label")
        var trashCalls = 0
        let texts = try seeded([entry], fixture: f) { url in trashCalls += 1; return url }
        let file = try texts.materialize(entry), bytes = try Data(contentsOf: file)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let files = try FileManager.default.contentsOfDirectory(atPath: texts.folder.path).sorted()
        f.date.addTimeInterval(1)
        XCTAssertTrue(texts.add(entry.text))
        XCTAssertEqual(texts.entries.first?.id, entry.id)
        XCTAssertEqual(texts.entries.first?.title, entry.title)
        XCTAssertEqual(texts.entries.first?.pinned, true)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date,
                       attributes[.modificationDate] as? Date)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: texts.folder.path).sorted(), files)
        XCTAssertEqual(trashCalls, 0)
    }

    func testRecopyCollapsesOnlyMatchingLegacyDuplicatesKeepingNewestIDAndMetadata() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let old = TextHistory.Entry(id: UUID(), text: "Repeated\n", capturedAt: f.date.addingTimeInterval(-30), pinned: true, title: "Old name")
        let useful = TextHistory.Entry(id: UUID(), text: "\r\nRepeated", capturedAt: f.date.addingTimeInterval(-20), pinned: false, title: "Newest useful name")
        let newest = TextHistory.Entry(id: UUID(), text: "Repeated", capturedAt: f.date.addingTimeInterval(-10), pinned: false)
        let untouched = TextHistory.Entry(id: UUID(), text: "Unrelated", capturedAt: f.date.addingTimeInterval(-5), pinned: false)
        let untouchedDuplicate = TextHistory.Entry(id: UUID(), text: "Unrelated", capturedAt: f.date.addingTimeInterval(-4), pinned: false)
        // Deliberately unsorted input proves that timestamp, not array position, wins.
        var trashCalls = 0
        let texts = try seeded([old, untouched, newest, useful, untouchedDuplicate], fixture: f) { url in trashCalls += 1; return url }
        XCTAssertTrue(texts.add("Repeated"))
        XCTAssertEqual(texts.entries.map(\.id), [newest.id, untouched.id, untouchedDuplicate.id])
        XCTAssertEqual(texts.entries.first?.title, useful.title)
        XCTAssertEqual(texts.entries.first?.pinned, true)
        XCTAssertEqual(texts.entries.first?.capturedAt, f.date)
        XCTAssertEqual(Array(texts.entries.dropFirst()), [untouched, untouchedDuplicate])
        XCTAssertEqual(f.texts().entries, texts.entries)
        XCTAssertEqual(trashCalls, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: texts.folder.path), ["history.json"])
    }

    func testArchiveFailureLeavesEntriesFocusSelectionScrollAndFilesUnchanged() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let texts = f.texts()
        XCTAssertTrue(texts.add("Synthetic A")); let first = try XCTUnwrap(texts.entries.first)
        f.date.addTimeInterval(1); XCTAssertTrue(texts.add("Synthetic B"))
        texts.select(first.id, width: 350); texts.scrollOffset = 19
        let previous = texts.entries, selected = texts.selectedIDs
        let bytes = try Data(contentsOf: texts.archive)
        let backup = texts.folder.appendingPathComponent("preserved-history.json")
        try FileManager.default.moveItem(at: texts.archive, to: backup)
        try FileManager.default.createSymbolicLink(at: texts.archive, withDestinationURL: backup)
        let files = try FileManager.default.contentsOfDirectory(atPath: texts.folder.path).sorted()
        f.date.addTimeInterval(1)
        XCTAssertFalse(texts.add("Synthetic A"))
        XCTAssertEqual(texts.entries, previous)
        XCTAssertEqual(texts.focusedID, first.id)
        XCTAssertEqual(texts.selectedIDs, selected)
        XCTAssertEqual(texts.scrollOffset, 19)
        XCTAssertEqual(try Data(contentsOf: backup), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: texts.folder.path).sorted(), files)
        try FileManager.default.removeItem(at: texts.archive)
        try FileManager.default.moveItem(at: backup, to: texts.archive)
        XCTAssertEqual(f.texts().entries, previous)
    }
}
