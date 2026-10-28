import AppKit
import Combine
import SwiftUI
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class ShelfProjectionTests: HistoryTestCase {
    private func records(_ count: Int, kind: LibraryKind, date: Date) -> [LibraryRecord] {
        (0..<count).map { index in
            var item = LibraryRecord(id: UUID(), kind: kind, createdAt: date.addingTimeInterval(Double(index)), updatedAt: date)
            item.title = "Synthetic \(kind.rawValue) \(index)"; item.favorite = index.isMultiple(of: 2)
            if kind == .text { item.text = "Synthetic body \(index)" }
            else { item.originalURL = "https://example.com/synthetic/\(index)"; item.normalizedURL = item.originalURL; item.metadataState = "ready" }
            return item
        }
    }
    private func store(_ f: SyntheticFixture) throws -> LibraryStore {
        try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date }, moveToTrash: fixtureTrash(f.folder))
    }
    func testTextProjectionInvalidatesForEditedPinnedAndRemovedEntries() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try store(f), values = records(6, kind: .text, date: f.date)
        try store.importRecords(values)
        let texts = TextHistory(defaults: f.defaults, folder: f.inbox.appendingPathComponent("Texts"), library: store)
        let ids = Set(values.map(\.id)), favorite = values[0].id, ordinary = values[1].id
        XCTAssertEqual(Set(texts.displayEntries.map(\.id)), ids)
        texts.setFavoritesOnly(true)
        XCTAssertEqual(Set(texts.displayEntries.map(\.id)), Set(values.filter(\.favorite).map(\.id)))
        texts.setSearchMatchingIDs([favorite, ordinary], width: 1000)
        XCTAssertEqual(texts.displayEntries.map(\.id), [favorite])
        texts.select(favorite, width: 1000); XCTAssertEqual(texts.selectedEntries.first?.id, favorite)
        XCTAssertTrue(texts.updateText(favorite, to: "Edited filtered body"))
        XCTAssertEqual(texts.displayEntries.first?.text, "Edited filtered body")
        XCTAssertEqual(texts.selectedEntries.first?.text, "Edited filtered body")
        try store.nameAndPin(favorite, name: "Edited filtered title")
        XCTAssertEqual(texts.displayEntries.first?.title, "Edited filtered title")
        XCTAssertEqual(texts.selectedEntries.first?.title, "Edited filtered title")
        texts.togglePin(ordinary)
        XCTAssertEqual(Set(texts.displayEntries.map(\.id)), [favorite, ordinary])
        texts.togglePin(favorite)
        XCTAssertEqual(texts.displayEntries.map(\.id), [ordinary])
        XCTAssertTrue(texts.selectedEntries.isEmpty)
        texts.select(ordinary, width: 1000); XCTAssertEqual(texts.selectedEntries.map(\.id), [ordinary])
        texts.setSearchMatchingIDs([], width: 1000); XCTAssertTrue(texts.displayEntries.isEmpty)
        texts.setSearchMatchingIDs(nil, width: 1000); texts.setFavoritesOnly(false)
        XCTAssertEqual(Set(texts.displayEntries.map(\.id)), ids)
        texts.trash([ordinary]); XCTAssertFalse(texts.displayEntries.contains { $0.id == ordinary })
    }
    func testLinkProjectionInvalidatesForMetadataOrderPinnedAndRemovedEntries() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try store(f), values = records(6, kind: .link, date: f.date)
        try store.importRecords(values); let links = LinkHistory(store: store)
        let favorite = values[0].id, ordinary = values[1].id
        links.setFavoritesOnly(true); links.setSearchMatchingIDs([favorite, ordinary], width: 1000)
        XCTAssertEqual(links.displayEntries.map(\.id), [favorite])
        links.select(favorite, width: 1000); XCTAssertEqual(links.selectedEntries.map(\.id), [favorite])
        try store.update(favorite) { $0.metadataTitle = "New synthetic metadata"; $0.thumbnailPath = "/synthetic/new-thumbnail.png" }
        XCTAssertEqual(links.displayEntries.first?.metadataTitle, "New synthetic metadata")
        XCTAssertEqual(links.selectedEntries.first?.metadataTitle, "New synthetic metadata")
        XCTAssertEqual(links.displayEntries.first?.thumbnailPath, "/synthetic/new-thumbnail.png")
        links.togglePin(ordinary); XCTAssertEqual(Set(links.displayEntries.map(\.id)), [favorite, ordinary])
        links.setSearchMatchingIDs(nil, width: 1000); links.setFavoritesOnly(false)
        f.date.addTimeInterval(20); try store.markCopied([favorite])
        XCTAssertEqual(links.displayEntries.first?.id, favorite, "Copied links keep their actual shelf ordering")
        links.removeFromShelf(favorite); XCTAssertFalse(links.displayEntries.contains { $0.id == favorite })
        XCTAssertTrue(links.selectedEntries.isEmpty)
        XCTAssertEqual(Set(links.displayEntries.map(\.id)), Set(values.dropFirst().map(\.id)))
    }
    func testClampedScrollDoesNotPublishAndStillClampsAfterViewportChange() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }; let store = try store(f)
        try store.importRecords(records(30, kind: .text, date: f.date) + records(30, kind: .link, date: f.date))
        let texts = TextHistory(defaults: f.defaults, folder: f.inbox.appendingPathComponent("Texts"), library: store)
        let links = LinkHistory(store: store)
        var textEvents = 0, linkEvents = 0
        let a = texts.$scrollOffset.dropFirst().sink { _ in textEvents += 1 }
        let b = links.$scrollOffset.dropFirst().sink { _ in linkEvents += 1 }; defer { a.cancel(); b.cancel() }
        for _ in 0..<100 { texts.scroll(0, width: 1000); texts.scroll(1, width: 1000); links.scroll(0, width: 1000); links.scroll(1, width: 1000) }
        texts.scroll(.nan, width: 1000); links.scroll(.infinity, width: 1000)
        XCTAssertEqual(textEvents, 0); XCTAssertEqual(linkEvents, 0)
        texts.scroll(-25, width: 1000); links.scroll(-25, width: 1000)
        XCTAssertEqual(texts.scrollOffset, 25); XCTAssertEqual(links.scrollOffset, 25)
        XCTAssertEqual(textEvents, 1); XCTAssertEqual(linkEvents, 1)
        texts.scroll(-100000, width: 1000); links.scroll(-100000, width: 1000)
        let maximum = Layout.maximumOffset(count: 30, width: 1000)
        XCTAssertEqual(texts.scrollOffset, maximum); XCTAssertEqual(links.scrollOffset, maximum)
        for _ in 0..<100 { texts.scroll(-1, width: 1000); links.scroll(-1, width: 1000) }
        XCTAssertEqual(textEvents, 2); XCTAssertEqual(linkEvents, 2)
        texts.scroll(0, width: 100000); links.scroll(0, width: 100000)
        XCTAssertEqual(texts.scrollOffset, 0); XCTAssertEqual(links.scrollOffset, 0)
        XCTAssertEqual(textEvents, 3); XCTAssertEqual(linkEvents, 3)
    }
    func testRenderStateIgnoresOtherShelfChangesButTracksVisibleInputs() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }; let store = try store(f)
        try store.importRecords(records(20, kind: .text, date: f.date) + records(20, kind: .link, date: f.date))
        let line = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false, library: store)
        line.setPresentation(.all, requestFocus: false); line.setViewportWidth(1000)
        let initialText = ShelfRenderState(line: line, shelf: .texts), initialLink = ShelfRenderState(line: line, shelf: .links)
        line.links.scroll(-100, width: 1000)
        XCTAssertEqual(ShelfRenderState(line: line, shelf: .texts), initialText)
        line.texts.scroll(-100, width: 1000)
        XCTAssertEqual(ShelfRenderState(line: line, shelf: .links), initialLink)
        line.focusShelf(.texts, requestFocus: false)
        let active = ShelfRenderState(line: line, shelf: .texts)
        XCTAssertFalse(active.quickIDs.isEmpty); XCTAssertNotEqual(active, initialText)
        line.draggingID = line.texts.entries[0].id
        XCTAssertNotEqual(ShelfRenderState(line: line, shelf: .texts), active)
        XCTAssertEqual(ShelfRenderState(line: line, shelf: .links).draggingID, nil)
        line.setTheme(.neutral)
        XCTAssertNotEqual(ShelfRenderState(line: line, shelf: .links), initialLink)
        line.setSize(.large)
        XCTAssertNotEqual(ShelfRenderState(line: line, shelf: .texts).scale, initialText.scale)
    }
    private func wait(_ predicate: () -> Bool, host: NSView) {
        let deadline = Date().addingTimeInterval(5)
        while !predicate() && Date() < deadline { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(predicate(), "Mounted shelf projection did not settle")
    }
    func testMountedRowsOnlyRequestVisibleLinkPayloadChanges() throws {
        _ = NSApplication.shared
        let f = try SyntheticFixture(); defer { f.cleanup() }; let store = try store(f)
        try store.importRecords(records(60, kind: .text, date: f.date) + records(60, kind: .link, date: f.date))
        let line = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false, library: store)
        line.setPresentation(.all, requestFocus: false); line.setViewportWidth(1000)
        var requests = [[UUID]](); line.onLinkItemsVisible = { requests.append($0) }
        let host = NSHostingView(rootView: LineView(line: line)); host.sizingOptions = []
        let panel = LinePanel(content: host); panel.contentHeight = line.panelHeight
        panel.setFrame(NSRect(x: -10000, y: -10000, width: 1000, height: line.panelHeight), display: false)
        defer { line.onLinkItemsVisible = nil; panel.contentView = nil }
        // NSHostingView may appear once at its intrinsic width before the
        // panel's actual viewport is applied. Observe that real layout first.
        let initial = Layout.visibleRange(count: line.links.displayEntries.count, width: 1000, offset: 0).map { line.links.displayEntries[$0].id }
        wait({ host.bounds.width == 1000 && requests.last == initial }, host: host)
        let first = try XCTUnwrap(requests.last), count = requests.count
        XCTAssertTrue(first.count < 12); XCTAssertFalse(first.contains(line.links.entries.last!.id))
        let last = try XCTUnwrap(line.links.entries.last?.id)
        try store.update(last) { $0.metadataTitle = "Offscreen title changed" }
        host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(requests.count, count, "Offscreen metadata does not repeat visible thumbnail/enrichment work")
        let visible = try XCTUnwrap(first.first)
        try store.update(visible) { $0.thumbnailPath = try f.image().path }
        wait({ requests.count == count + 1 }, host: host)
        XCTAssertEqual(requests.last, first)
        line.links.scroll(-100000, width: 1000)
        wait({ requests.last?.contains(last) == true }, host: host)
        let expected = Layout.visibleRange(count: line.links.displayEntries.count, width: 1000, offset: line.links.scrollOffset).map { line.links.displayEntries[$0].id }
        XCTAssertEqual(requests.last, expected)
    }
}
