import AppKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class TextIdentityParityTests: HistoryTestCase {
    private struct Contract: Decodable { let schemaVersion: Int; let cases: [Entry] }
    private struct Entry: Decodable { let id: String; let copies: [String] }

    func testSharedTextIdentitiesAgainstLibraryAndLegacyHistory() throws {
        let checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let contract = try JSONDecoder().decode(Contract.self, from: Data(contentsOf: checkout.appendingPathComponent("contracts/text-identity.json")))
        XCTAssertEqual(contract.schemaVersion, 1)
        let fixture = try SyntheticFixture(); defer { fixture.cleanup() }
        let library = try LibraryStore(defaults: fixture.defaults, inbox: fixture.inbox, now: { fixture.date }, moveToTrash: fixtureTrash(fixture.folder))
        let legacy = fixture.texts()
        let folder = try library.createCollection("Synthetic references")
        var libraryIDs = Set<UUID>(), legacyIDs = Set<UUID>()
        for entry in contract.cases {
            let first = try XCTUnwrap(library.captureText(try XCTUnwrap(entry.copies.first)))
            try library.nameAndPin(first.id, name: entry.id)
            try library.assign([first.id], to: folder)
            try library.addTag("synthetic", to: [first.id])
            try library.update(first.id) { $0.note = "Personal synthetic note" }
            let retained = try library.item(first.id)?.retainedAt
            XCTAssertTrue(legacy.add(entry.copies[0]))
            let legacyID = try XCTUnwrap(legacy.entries.first?.id)
            for body in entry.copies {
                fixture.date.addTimeInterval(1)
                let latest = try XCTUnwrap(library.captureText(body))
                XCTAssertEqual(latest.id, first.id, entry.id)
                XCTAssertEqual(Data((latest.text ?? "").utf8), Data(body.utf8), entry.id)
                XCTAssertEqual(latest.title, entry.id); XCTAssertTrue(latest.favorite)
                XCTAssertEqual(latest.note, "Personal synthetic note"); XCTAssertEqual(latest.retainedAt, retained)
                XCTAssertEqual(try library.collections(for: first.id).map(\.id), [folder])
                XCTAssertEqual(try library.tags(for: first.id).map(\.name), ["synthetic"])
                XCTAssertEqual(try library.shelfItems(.text).first?.id, first.id)
                XCTAssertTrue(legacy.add(body)); XCTAssertEqual(legacy.entries.first?.id, legacyID, entry.id)
                XCTAssertEqual(Data((legacy.entries.first?.text ?? "").utf8), Data(body.utf8), entry.id)
            }
            libraryIDs.insert(first.id); legacyIDs.insert(legacyID)
        }
        XCTAssertEqual(libraryIDs.count, contract.cases.count)
        XCTAssertEqual(legacyIDs.count, contract.cases.count)
        XCTAssertEqual(try library.shelfItems(.text).count, contract.cases.count)
        XCTAssertEqual(legacy.entries.count, contract.cases.count)
    }
}
