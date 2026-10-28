import AppKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class NamedShelfLabelTests: HistoryTestCase {
    func testRenamingPinnedImageRefreshesShelfLabelWithoutChangingImageOrSelection() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date }, moveToTrash: fixtureTrash(f.folder))
        let record = try store.captureImage(f.image())
        let line = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false,
            copyImage: { _ in }, copyText: { _ in }, library: store)
        line.select(record.id)
        try store.nameAndPin(record.id, name: "Initial title")
        let url = try XCTUnwrap(line.items.first?.url)
        XCTAssertEqual(line.items.first?.title, "Initial title")
        try store.nameAndPin(record.id, name: "Renamed screenshot")
        XCTAssertEqual(line.items.first?.title, "Renamed screenshot")
        XCTAssertEqual(line.items.first?.url, url)
        XCTAssertEqual(line.focusedID, record.id)
        XCTAssertTrue(line.items.first?.pinned == true)
    }
}
