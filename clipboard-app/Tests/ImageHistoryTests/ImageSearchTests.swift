import AppKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class ImageSearchTests: HistoryTestCase {
    private func wait(_ predicate: () -> Bool) {
        let end = Date().addingTimeInterval(30)
        while !predicate() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(predicate(), "Background image indexing did not complete")
    }
    private func draw(_ url: URL, text: String? = nil, color: NSColor = .red, circle: Bool = true) throws {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 500, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 800, height: 500)).fill()
        if let text { (text as NSString).draw(at: NSPoint(x: 50, y: 210), withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black]) }
        else { color.setFill(); (circle ? NSBezierPath(ovalIn: NSRect(x: 220, y: 70, width: 360, height: 360)) : NSBezierPath(rect: NSRect(x: 220, y: 70, width: 360, height: 360))).fill() }
        NSGraphicsContext.restoreGraphicsState()
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }
    func testLanguagePreferencePersistsRejectsInvalidAndRestoresSystemWithoutChangingOtherPreferences() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        f.defaults.set(7, forKey: "textHistoryRetentionDays")
        XCTAssertTrue(LanguagePreferences.set("tr", defaults: f.defaults, languages: ["en", "tr"]))
        XCTAssertEqual(LanguagePreferences.selection(try XCTUnwrap(UserDefaults(suiteName: f.suite))), "tr")
        XCTAssertEqual(f.defaults.stringArray(forKey: "AppleLanguages"), ["tr"])
        XCTAssertFalse(LanguagePreferences.set("../unknown", defaults: f.defaults, languages: ["en", "tr"]))
        XCTAssertEqual(LanguagePreferences.selection(f.defaults), "tr")
        XCTAssertTrue(LanguagePreferences.set("", defaults: f.defaults, languages: ["en", "tr"]))
        XCTAssertNil(f.defaults.persistentDomain(forName: f.suite)?["AppleLanguages"]); XCTAssertEqual(f.defaults.integer(forKey: "textHistoryRetentionDays"), 7)
    }
    func testStatusCountsOnlyEnabledShelvesAndKeepsExactTotalsWithCappedBadge() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        let line = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false, library: store); _ = line.hang(try f.image(), quietly: true)
        _ = line.texts.add("One"); _ = line.texts.add("Two")
        _ = line.links.add(try XCTUnwrap(URL(string: "https://example.com/one")))
        line.setPresentation(.all, requestFocus: false)
        XCTAssertEqual(StatusSummary(line: line), StatusSummary(images: 1, texts: 2, links: 1))
        line.setShelfVisible(.images, visible: false)
        XCTAssertEqual(StatusSummary(line: line).count, 3)
        line.setShelfVisible(.texts, visible: false)
        XCTAssertEqual(StatusSummary(line: line).count, 1)
        XCTAssertEqual(StatusSummary(images: 10, texts: 50, links: 3).badge, "9+")
        XCTAssertEqual(StatusSummary(images: 0, texts: 0, links: 0).badge, "0")
    }
    func testOCRIndexIsPersistentCachedAndPreservesPayloadThenReindexesEditedPixels() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date }), url = try f.image()
        try draw(url, text: "ORBITAL 8427")
        let item = try store.captureImage(url), before = try store.item(item.id)
        let worker = ImageSearchWorker(database: store.databaseURL, modelFolder: nil); defer { worker.cancel() }
        var done = false, updates = false
        worker.scan { a, b, changed in updates = updates || changed; if a == b { done = true } }; wait { done }
        XCTAssertTrue(updates); XCTAssertEqual(try store.item(item.id), before)
        var query = LibraryQuery(scope: .recent); query.search = "orbital 8427"
        XCTAssertEqual(try store.queryIDs(query), [item.id])
        let reopened = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        XCTAssertEqual(try reopened.queryIDs(query), [item.id])
        done = false; updates = false
        worker.scan { a, b, changed in updates = updates || changed; if a == b { done = true } }; wait { done }
        XCTAssertFalse(updates, "Unchanged pixels should not be read again")
        try draw(url, text: "NEBULA 9631")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: url.path)
        done = false; worker.scan { a, b, _ in if a == b { done = true } }; wait { done }
        XCTAssertTrue(try store.queryIDs(query).isEmpty)
        query.search = "nebula 9631"; XCTAssertEqual(try store.queryIDs(query), [item.id])
        XCTAssertEqual(try store.item(item.id), before)
    }
    func testVisualSuggestionsHonorScopeKindPinTagAndTrashAndTextMatchesRankFirst() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let store = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date })
        let a = try store.captureImage(f.image(), capturedAt: f.date.addingTimeInterval(-20)), b = try store.captureImage(f.image(), capturedAt: f.date.addingTimeInterval(-10))
        try store.toggleFavorite([a.id]); try store.retain([b.id]); try store.addTag("topic", to: [a.id])
        let note = try store.createNote(); try store.update(note.id) { $0.text = "red circle" }
        var q = LibraryQuery(); q.search = "red circle"; q.visualIDs = [b.id, a.id]; q.sort = .relevance
        XCTAssertEqual(try store.queryIDs(q), [note.id, b.id, a.id])
        q.sort = .oldest; XCTAssertEqual(try store.queryIDs(q), [a.id, b.id, note.id]); q.sort = .relevance
        q.favoritesOnly = true; XCTAssertEqual(try store.queryIDs(q), [a.id])
        q.favoritesOnly = false; q.tagIDs = [try XCTUnwrap(store.tags().first).id]; XCTAssertEqual(try store.queryIDs(q), [a.id])
        q.tagIDs = []; q.kind = .text; XCTAssertEqual(try store.queryIDs(q), [note.id])
        q.kind = .image; q.scope = .recent; XCTAssertTrue(try store.queryIDs(q).isEmpty)
        try store.trash([a.id]); q.scope = .saved; XCTAssertEqual(try store.queryIDs(q), [b.id])
        q.scope = .trash; XCTAssertEqual(try store.queryIDs(q), [a.id])
        q.scope = .saved; q.kind = nil; q.searchMode = .text; XCTAssertEqual(try store.queryIDs(q), [note.id])
    }
    func testMalformedOrUnrelatedVisualVectorsDoNotCreateMatches() throws {
        let vector = [Float](repeating: 0, count: 511) + [1]
        XCTAssertEqual(VisualRanking.score(vector, VisualRanking.pack([vector])), 1)
        XCTAssertNil(VisualRanking.score(vector, Data([1, 2, 3])))
        XCTAssertNil(VisualRanking.score([.nan] + vector.dropFirst(), VisualRanking.pack([vector])))
        XCTAssertTrue(VisualRanking.matches([(UUID(), 0.1), (UUID(), .nan)]).isEmpty)
    }
    func testMobileCLIPFindsImageContentWithoutOCRAndTokenizerMatchesReference() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("local/models/MobileCLIP")
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("model-source.json").path) else {
            #if !STANDALONE_TESTS
            throw XCTSkip("Prepare offline search models to run the native model integration")
            #else
            return
            #endif
        }
        let model = try XCTUnwrap(Clip(folder: folder)), tokenizer = try XCTUnwrap(ClipTokenizer(vocab: folder.appendingPathComponent("clip-vocab.json"), merges: folder.appendingPathComponent("clip-merges.txt")))
        XCTAssertEqual(tokenizer.encode("hello world"), [49406, 3306, 1002, 49407])
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let red = try f.image(), blue = try f.image(), green = try f.image()
        try draw(red); try draw(blue, color: .blue, circle: false); try draw(green, color: .green, circle: false)
        let query = try XCTUnwrap(model.embed(text: "a red circle on a white background")), a = UUID(), b = UUID(), c = UUID()
        let scores = [(a, red), (b, blue), (c, green)].map { ($0.0, VisualRanking.score(query, VisualRanking.pack(model.embed(imageAt: $0.1))) ?? -1) }
        XCTAssertEqual(VisualRanking.matches(scores).first, a, "Native semantic scores: \(scores.map(\.1))")
        XCTAssertTrue(try ImageSearchWorker.recognize(red).isEmpty, "The image match must not depend on text")
    }
}
