import AppKit
import AVFoundation
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class RecordingTrimPersistenceTests: HistoryTestCase {
    private func store(_ f: SyntheticFixture) throws -> LibraryStore {
        try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date }, moveToTrash: fixtureTrash(f.folder))
    }
    private func movie(_ f: SyntheticFixture, ext: String = "mp4") throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let relative = "windows/tests/fixtures/recordings/synthetic-rgb-tone.\(ext)"
        let candidates = [root.appendingPathComponent(relative), root.appendingPathComponent("local/public-source/clipboardline-desktop/" + relative)]
        let source = try XCTUnwrap(candidates.first { FileManager.default.fileExists(atPath: $0.path) })
        let target = f.folder.appendingPathComponent("Original reference.\(ext)")
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }
    private func render(_ context: LibraryStore.RecordingTrimContext, start: Double = 2, end: Double = 4) async throws {
        let session = try XCTUnwrap(AVAssetExportSession(asset: AVURLAsset(url: context.snapshot), presetName: AVAssetExportPresetPassthrough))
        session.outputURL = context.output
        session.outputFileType = context.output.pathExtension == "mp4" ? .mp4 : .mov
        session.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
        await session.export()
        guard session.status == .completed else { throw session.error ?? HistoryFiles.Failure.unsafeFile }
    }
    private func duration(_ url: URL) async throws -> Double { try await AVURLAsset(url: url).load(.duration).seconds }
    private func expectRejected(_ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Unsafe or canceled trim unexpectedly committed", file: file, line: line) } catch { }
    }
    private func greenFrame(_ url: URL) async throws {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url)); generator.appliesPreferredTrackTransform = true
        let image = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self), at = (image.height / 2 * image.width + image.width / 2) * 4
        XCTAssertGreaterThan(Int(pixels[at + 1]), Int(pixels[at]) + 80)
        XCTAssertGreaterThan(Int(pixels[at + 1]), Int(pixels[at + 2]) + 80)
    }
    func testExternalUnsavedMP4AndMOVTrimKeepOriginalAndStableHistoryIdentity() async throws {
        for ext in ["mp4", "mov"] {
            let f = try SyntheticFixture(); defer { f.cleanup() }; let library = try store(f)
            let original = try movie(f, ext: ext), bytes = try Data(contentsOf: original), initial = try library.captureImage(original)
            let context = try await library.prepareRecordingTrim(initial.id)
            XCTAssertTrue(library.files.isFavoriteCopy(context.snapshot)); XCTAssertEqual(try Data(contentsOf: context.snapshot), bytes)
            XCTAssertEqual(try library.item(initial.id), initial); XCTAssertFalse(FileManager.default.fileExists(atPath: context.output.path))
            try await render(context)
            let edited = try await library.commitRecordingTrim(context), active = try XCTUnwrap(edited.fileURL), base = try XCTUnwrap(edited.recordingOriginalURL)
            XCTAssertEqual(edited.id, initial.id); XCTAssertEqual(edited.createdAt, initial.createdAt)
            XCTAssertNil(edited.retainedAt); XCTAssertFalse(edited.favorite); XCTAssertTrue(edited.onShelf)
            XCTAssertEqual(edited.originalPath, original.path); XCTAssertEqual(edited.exportFileName, original.lastPathComponent)
            XCTAssertEqual(try Data(contentsOf: original), bytes); XCTAssertEqual(try Data(contentsOf: base), bytes)
            XCTAssertNotEqual(active, original); XCTAssertNotEqual(active, base); XCTAssertTrue(library.files.isFavoriteCopy(active))
            let seconds = try await duration(active); XCTAssertEqual(seconds, 2, accuracy: 0.2)
            let originalSeconds = try await duration(original); XCTAssertEqual(originalSeconds, 6, accuracy: 0.1)
            try await greenFrame(active)
            let audio = try await AVURLAsset(url: active).loadTracks(withMediaType: .audio); XCTAssertEqual(audio.count, 1)
            for url in [active, base] { XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600) }
            let reopened = try store(f), restored = try XCTUnwrap(reopened.item(initial.id))
            XCTAssertEqual(restored.recordingOriginalPath, base.path); XCTAssertEqual(restored.path, active.path)
            let adapter = ImageHistory(defaults: f.defaults, inbox: f.inbox, library: reopened)
            XCTAssertEqual(adapter.entries.first?.id, initial.id); XCTAssertEqual(adapter.entries.first?.url, active)
            let owned = library.files.files(in: library.files.favoritesFolder, matching: library.files.isFavoriteCopy)
            let backedUp = Set(owned.map { $0.resolvingSymlinksInPath().path })
            XCTAssertTrue(backedUp.contains(base.resolvingSymlinksInPath().path))
            XCTAssertTrue(backedUp.contains(active.resolvingSymlinksInPath().path))
        }
    }
    func testRepeatedTrimPreservesFirstBytesAndCurrentOrganizationWithoutPromotingRetention() async throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }; let library = try store(f)
        let original = try movie(f), bytes = try Data(contentsOf: original), item = try library.captureImage(original)
        let folder = try library.createCollection("Video references"); try library.assign([item.id], to: folder, pinning: true)
        try library.update(item.id) { $0.note = "Original note"; $0.title = "Reference recording" }
        let first = try await library.prepareRecordingTrim(item.id)
        try await render(first, start: 2, end: 5)
        try library.addTag("New organization", to: [item.id]); try library.update(item.id) { $0.note = "Latest note" }
        try library.toggleFavorite([item.id])
        let saved = try await library.commitRecordingTrim(first), base = try XCTUnwrap(saved.recordingOriginalURL), previous = try XCTUnwrap(saved.fileURL)
        let second = try await library.prepareRecordingTrim(item.id); try await render(second, start: 0, end: 1)
        let repeated = try await library.commitRecordingTrim(second)
        XCTAssertEqual(repeated.id, item.id); XCTAssertEqual(repeated.recordingOriginalURL, base)
        XCTAssertEqual(repeated.retainedAt, saved.retainedAt); XCTAssertFalse(repeated.favorite)
        XCTAssertEqual(repeated.title, "Reference recording"); XCTAssertEqual(repeated.note, "Latest note")
        XCTAssertEqual(try library.collections(for: item.id).map(\.id), [folder]); XCTAssertEqual(try library.tags(for: item.id).map(\.name), ["New organization"])
        XCTAssertEqual(try Data(contentsOf: original), bytes); XCTAssertEqual(try Data(contentsOf: base), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: previous.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: second.snapshot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(repeated.path)))
    }
    func testChangedExternalSourceAndDeletedTargetCannotPublishAnOldExport() async throws {
        for deleted in [false, true] {
            let f = try SyntheticFixture(); defer { f.cleanup() }; let library = try store(f)
            let original = try movie(f), item = try library.captureImage(original), context = try await library.prepareRecordingTrim(item.id)
            try await render(context)
            if deleted { try library.trash([item.id]) } else { let handle = try FileHandle(forWritingTo: original); try handle.seekToEnd(); try handle.write(contentsOf: Data([0, 0, 0, 8, 102, 114, 101, 101])); try handle.close() }
            let before = try library.item(item.id), bytes = try Data(contentsOf: original)
            await expectRejected { _ = try await library.commitRecordingTrim(context) }
            XCTAssertEqual(try library.item(item.id), before); XCTAssertEqual(try Data(contentsOf: original), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: context.snapshot.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: context.output.path))
        }
    }
    func testNewerRecordingGenerationRejectsConcurrentStaleTrim() async throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }; let library = try store(f)
        let item = try library.captureImage(try movie(f)), first = try await library.prepareRecordingTrim(item.id), second = try await library.prepareRecordingTrim(item.id)
        try await render(first); try await render(second, start: 1, end: 5)
        let saved = try await library.commitRecordingTrim(first)
        await expectRejected { _ = try await library.commitRecordingTrim(second) }
        XCTAssertEqual(try library.item(item.id), saved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(saved.recordingOriginalPath)))
    }
    func testCancelBeforeCommitOrDuringValidationKeepsOriginalAndDiscardsOnlyStaging() async throws {
        for discard in [false, true] {
            let f = try SyntheticFixture(); defer { f.cleanup() }; let library = try store(f)
            let original = try movie(f), initial = try library.captureImage(original), context = try await library.prepareRecordingTrim(initial.id)
            try await render(context)
            if discard { library.discardRecordingTrim(context); await expectRejected { _ = try await library.commitRecordingTrim(context) } }
            else { let task = Task { try await library.commitRecordingTrim(context) }; task.cancel(); await expectRejected { _ = try await task.value } }
            XCTAssertEqual(try library.item(initial.id), initial)
            XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: context.output.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: context.snapshot.path))
        }
    }
    func testFailedRecordingTransactionRollsBackAndALaterRetryCanCommit() async throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }; let library = try store(f)
        let original = try movie(f), bytes = try Data(contentsOf: original), item = try library.captureImage(original), context = try await library.prepareRecordingTrim(item.id)
        try await render(context)
        let connection = try LibraryDatabase(url: library.databaseURL)
        try connection.execute("CREATE TRIGGER reject_recording BEFORE UPDATE ON items BEGIN SELECT RAISE(ABORT,'synthetic failure'); END")
        await expectRejected { _ = try await library.commitRecordingTrim(context) }
        XCTAssertEqual(try library.item(item.id), item); XCTAssertEqual(try Data(contentsOf: original), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.output.path))
        try connection.execute("DROP TRIGGER reject_recording")
        let retry = try await library.prepareRecordingTrim(item.id); try await render(retry)
        let saved = try await library.commitRecordingTrim(retry); XCTAssertNotEqual(saved.path, item.path)
    }
    func testCleanupProtectsInFlightSnapshotAndPersistedOriginalAcrossRestart() async throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }; let library = try store(f)
        let item = try library.captureImage(try movie(f)), context = try await library.prepareRecordingTrim(item.id)
        // Discarding another session drains the same durable queue. This one is
        // still reading/exporting and must remain protected until it finishes.
        let other = try await library.prepareRecordingTrim(item.id); library.discardRecordingTrim(other)
        XCTAssertTrue(FileManager.default.fileExists(atPath: context.snapshot.path))
        try await render(context); let saved = try await library.commitRecordingTrim(context)
        let base = try XCTUnwrap(saved.recordingOriginalPath), active = try XCTUnwrap(saved.path), db = try LibraryDatabase(url: library.databaseURL)
        for path in [base, active] { try db.execute("INSERT OR IGNORE INTO image_markup_garbage VALUES(?)", [.text(path)]) }
        _ = try store(f)
        XCTAssertTrue(FileManager.default.fileExists(atPath: base)); XCTAssertTrue(FileManager.default.fileExists(atPath: active))
    }
    func testMalformedExportAndSymlinkCannotChangeSourceOrRecord() async throws {
        for symlink in [false, true] {
            let f = try SyntheticFixture(); defer { f.cleanup() }; let library = try store(f)
            let original = try movie(f), bytes = try Data(contentsOf: original), item = try library.captureImage(original), context = try await library.prepareRecordingTrim(item.id)
            if symlink { try FileManager.default.createSymbolicLink(at: context.output, withDestinationURL: original) }
            else { try Data("Not a video".utf8).write(to: context.output) }
            await expectRejected { _ = try await library.commitRecordingTrim(context) }
            XCTAssertEqual(try library.item(item.id), item); XCTAssertEqual(try Data(contentsOf: original), bytes)
        }
    }
}
