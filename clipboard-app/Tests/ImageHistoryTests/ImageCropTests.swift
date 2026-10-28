import AppKit
import ImageIO
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class ImageCropTests: HistoryTestCase {
    private var temporary: [URL] = []

    private func cleanup() {
        for url in temporary { try? FileManager.default.removeItem(at: url) }
        temporary.removeAll()
    }

    private func source(width: Int = 100, height: Int = 80, transparent: Bool = false,
                        orientation: Int? = nil) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("crop-test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        temporary.append(folder)
        let url = folder.appendingPathComponent(orientation == nil ? "source.png" : "source.tiff")
        // CGImage file order: red/green across the top, blue/yellow below.
        let colors: [[UInt8]] = [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255], [255, 255, 0, 255]]
        let bytes = Data((0..<(width * height)).flatMap { index -> [UInt8] in
            transparent ? [0, 0, 0, 0] : colors[(index / width < height / 2 ? 0 : 2) + (index % width < width / 2 ? 0 : 1)]
        })
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: try XCTUnwrap(CGDataProvider(data: bytes as CFData)), decode: nil,
            shouldInterpolate: false, intent: .defaultIntent))
        let type = orientation == nil ? "public.png" : "public.tiff"
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil))
        let properties: [CFString: Any] = orientation.map { [kCGImagePropertyOrientation: $0] } ?? [:]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func decoded(_ data: Data) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// Sample using the same bottom-left coordinates as the crop document.
    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [Int] {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.translateBy(x: -CGFloat(x), y: -CGFloat(y))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return (0..<4).map { Int(bytes[$0]) }
    }

    func testCropDocumentDecodesLegacyAndRoundTripsWithoutChangingVersion() throws {
        let legacy = Data(#"{"version":1,"elements":[]}"#.utf8)
        let document = try JSONDecoder().decode(ImageMarkupDocument.self, from: legacy)
        XCTAssertNil(document.crop); XCTAssertTrue(document.isEmpty); XCTAssertEqual(document.version, 1)
        let crop = MarkupCrop(x: 0.1, y: 0.2, width: 0.6, height: 0.5)
        let cropped = ImageMarkupDocument(crop: crop)
        XCTAssertFalse(cropped.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(ImageMarkupDocument.self, from: JSONEncoder().encode(cropped)), cropped)
        XCTAssertEqual(crop.rect(in: NSRect(x: 10, y: 20, width: 200, height: 100)), NSRect(x: 30, y: 40, width: 120, height: 50))
        XCTAssertTrue(ImageMarkupDocument(crop: .full).isEmpty)
        XCTAssertTrue(MarkupCrop.full.isFullImage)
        XCTAssertFalse(crop.isFullImage)
    }

    func testCropValidationRejectsNonFiniteEmptyAndOutsideOriginalBounds() throws {
        let invalid = [
            MarkupCrop(x: .nan, y: 0, width: 0.5, height: 0.5),
            MarkupCrop(x: 0, y: .infinity, width: 0.5, height: 0.5),
            MarkupCrop(x: 0, y: 0, width: .infinity, height: 0.5),
            MarkupCrop(x: 0, y: 0, width: 0.5, height: .nan),
            MarkupCrop(x: -0.01, y: 0, width: 0.5, height: 0.5),
            MarkupCrop(x: 0, y: -0.01, width: 0.5, height: 0.5),
            MarkupCrop(x: 0, y: 0, width: 0, height: 0.5),
            MarkupCrop(x: 0, y: 0, width: 0.5, height: -0.1),
            MarkupCrop(x: 0.6, y: 0, width: 0.5, height: 0.5),
            MarkupCrop(x: 0, y: 0.6, width: 0.5, height: 0.5),
            MarkupCrop(x: 0, y: 0, width: 1.01, height: 1),
            MarkupCrop(x: 1, y: 0, width: 0.1, height: 1)
        ]
        for crop in invalid {
            XCTAssertFalse(crop.isValid)
            XCTAssertThrowsError(try ImageMarkupDocument(crop: crop).validated())
        }
        let invalidJSON = Data(#"{"version":1,"elements":[],"crop":{"x":0.8,"y":0,"width":0.5,"height":1}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ImageMarkupDocument.self, from: invalidJSON))
        XCTAssertTrue(MarkupCrop(x: 0.1, y: 0.1, width: 0.9, height: 0.9).isValid)
        XCTAssertTrue(MarkupCrop(x: 0, y: 0, width: Double.leastNonzeroMagnitude, height: Double.leastNonzeroMagnitude).isValid)
    }

    func testCropUsesBottomLeftQuadrantsAndFullResolutionPixels() throws {
        defer { cleanup() }
        let url = try source(width: 1600, height: 900)
        let cases: [(MarkupCrop, [Int])] = [
            (.init(x: 0, y: 0, width: 0.5, height: 0.5), [0, 0, 255, 255]),
            (.init(x: 0.5, y: 0, width: 0.5, height: 0.5), [255, 255, 0, 255]),
            (.init(x: 0, y: 0.5, width: 0.5, height: 0.5), [255, 0, 0, 255]),
            (.init(x: 0.5, y: 0.5, width: 0.5, height: 0.5), [0, 255, 0, 255])
        ]
        for (crop, color) in cases {
            let image = try decoded(ImageMarkupRenderer.render(sourceURL: url, document: .init(crop: crop)))
            XCTAssertEqual(image.width, 800); XCTAssertEqual(image.height, 450)
            XCTAssertEqual(try pixel(image, x: 400, y: 225), color)
        }
    }

    func testCropRoundsOutwardAndTinySelectionAlwaysProducesAtLeastOnePixel() throws {
        defer { cleanup() }
        let url = try source()
        let crop = MarkupCrop(x: 0.101, y: 0.203, width: 0.502, height: 0.504)
        let image = try decoded(ImageMarkupRenderer.render(sourceURL: url, document: .init(crop: crop)))
        XCTAssertEqual(image.width, 51); XCTAssertEqual(image.height, 41)
        for crop in [MarkupCrop(x: 0, y: 0, width: Double.leastNonzeroMagnitude, height: Double.leastNonzeroMagnitude),
                     MarkupCrop(x: 0.999999, y: 0.999999, width: 0.000001, height: 0.000001)] {
            let tiny = try decoded(ImageMarkupRenderer.render(sourceURL: url, document: .init(crop: crop)))
            XCTAssertEqual(tiny.width, 1); XCTAssertEqual(tiny.height, 1)
        }
        let full = try decoded(ImageMarkupRenderer.render(sourceURL: url, document: .init(crop: .full)))
        XCTAssertEqual(full.width, 100); XCTAssertEqual(full.height, 80)
    }

    func testCropAfterEXIFOrientationSelectsDisplayedTopLeft() throws {
        defer { cleanup() }
        let colors = [[255, 0, 0, 255], [0, 255, 0, 255], [255, 255, 0, 255], [0, 0, 255, 255],
                      [255, 0, 0, 255], [0, 0, 255, 255], [255, 255, 0, 255], [0, 255, 0, 255]]
        for orientation in 1...8 {
            let url = try source(width: 100, height: 60, orientation: orientation)
            let crop = MarkupCrop(x: 0, y: 0.5, width: 0.5, height: 0.5)
            let image = try decoded(ImageMarkupRenderer.render(sourceURL: url, document: .init(crop: crop)))
            XCTAssertEqual(image.width, orientation >= 5 ? 30 : 50)
            XCTAssertEqual(image.height, orientation >= 5 ? 50 : 30)
            XCTAssertEqual(try pixel(image, x: image.width / 2, y: image.height / 2), colors[orientation - 1])
        }
    }

    func testCropCompositesOriginalCoordinateAnnotationsAndRetainsAlphaWithoutMutatingSource() throws {
        defer { cleanup() }
        let url = try source(width: 200, height: 120, transparent: true), original = try Data(contentsOf: url)
        let mark = ImageMarkupElement(tool: .rectangle, points: [.init(x: 0.3, y: 0.3), .init(x: 0.7, y: 0.7)],
                                      color: .blue, fill: true)
        let document = ImageMarkupDocument(elements: [mark], crop: .init(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        let image = try decoded(ImageMarkupRenderer.render(sourceURL: url, document: document))
        XCTAssertEqual(image.width, 100); XCTAssertEqual(image.height, 60)
        let center = try pixel(image, x: 50, y: 30)
        XCTAssertTrue(center[2] > 240 && center[0] < 30 && center[3] == 255)
        XCTAssertEqual(try pixel(image, x: 0, y: 0), [0, 0, 0, 0])
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertFalse(ImageMarkupDocument(elements: [mark], crop: .full).isEmpty)
    }

    func testCropOnlyPersistsReopensRecropsOriginalAndResetsWithoutLosingOrganization() throws {
        defer { cleanup() }
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let library = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date }, moveToTrash: fixtureTrash(f.folder))
        let original = try source(width: 100, height: 80), bytes = try Data(contentsOf: original)
        let item = try library.captureImage(original), folder = try library.createCollection("Crop references")
        try library.assign([item.id], to: folder); try library.addTag("crop", to: [item.id]); try library.toggleFavorite([item.id])
        try library.update(item.id) { $0.title = "Reference"; $0.note = "Keep this note" }
        let before = try XCTUnwrap(library.item(item.id))
        let firstDocument = ImageMarkupDocument(crop: .init(x: 0, y: 0, width: 0.5, height: 0.5))
        let first = try library.saveImageMarkup(item.id, document: firstDocument), base = try XCTUnwrap(first.markupSourceURL)
        XCTAssertEqual(first.id, item.id); XCTAssertEqual(first.createdAt, item.createdAt)
        XCTAssertEqual(first.retainedAt, before.retainedAt); XCTAssertEqual(first.favorite, before.favorite)
        XCTAssertEqual(first.title, before.title); XCTAssertEqual(first.note, before.note)
        XCTAssertEqual(try library.collections(for: item.id).map(\.id), [folder])
        XCTAssertEqual(try library.tags(for: item.id).map(\.name), ["crop"])
        XCTAssertEqual(try Data(contentsOf: original), bytes); XCTAssertEqual(try Data(contentsOf: base), bytes)
        let reopened = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date }, moveToTrash: fixtureTrash(f.folder))
        XCTAssertEqual(try reopened.item(item.id)?.imageMarkup, firstDocument)
        let next = try reopened.saveImageMarkup(item.id, document: .init(crop: .init(x: 0.5, y: 0.5, width: 0.5, height: 0.5)))
        XCTAssertEqual(next.markupSourceURL, base)
        let image = try decoded(Data(contentsOf: XCTUnwrap(next.fileURL)))
        XCTAssertEqual(image.width, 50); XCTAssertEqual(image.height, 40)
        XCTAssertEqual(try pixel(image, x: 25, y: 20), [0, 255, 0, 255])
        let copied = try LibraryTransfer.pasteboardItems([next])
        let copy = try decoded(XCTUnwrap(copied.first?.data(forType: .png)))
        XCTAssertEqual(copy.width, 50); XCTAssertEqual(copy.height, 40)
        let restored = try reopened.saveImageMarkup(item.id, document: .init(crop: .full))
        XCTAssertEqual(restored.fileURL, base); XCTAssertNil(restored.imageMarkup); XCTAssertNil(restored.markupBasePath)
        XCTAssertEqual(restored.title, before.title); XCTAssertEqual(restored.note, before.note); XCTAssertEqual(restored.favorite, before.favorite)
        XCTAssertEqual(try Data(contentsOf: base), bytes); XCTAssertEqual(try Data(contentsOf: original), bytes)
    }

    func testCropInvalidatesOCRAndInvalidCropLeavesStoredPixelsUnchanged() throws {
        defer { cleanup() }
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let library = try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date }, moveToTrash: fixtureTrash(f.folder))
        let item = try library.captureImage(try source()), connection = try LibraryDatabase(url: library.databaseURL)
        try connection.execute("INSERT INTO image_analysis VALUES(?,?,?,?,?,?,?)", [.text(item.id.uuidString), .text(try XCTUnwrap(item.path)),
            .text("old"), .text("v1"), .text("old OCR"), .text("old OCR"), .blob(Data())])
        let edited = try library.saveImageMarkup(item.id, document: .init(crop: .init(x: 0, y: 0, width: 0.5, height: 0.5)))
        XCTAssertTrue(try connection.rows("SELECT item FROM image_analysis").isEmpty)
        let bytes = try Data(contentsOf: XCTUnwrap(edited.fileURL))
        XCTAssertThrowsError(try library.saveImageMarkup(item.id, document: .init(crop: .init(x: 0.9, y: 0, width: 0.5, height: 1))))
        XCTAssertEqual(try library.item(item.id), edited); XCTAssertEqual(try Data(contentsOf: XCTUnwrap(edited.fileURL)), bytes)
        try connection.execute("INSERT INTO image_analysis VALUES(?,?,?,?,?,?,?)", [.text(item.id.uuidString), .text(try XCTUnwrap(edited.path)),
            .text("cropped"), .text("v1"), .text("cropped OCR"), .text("cropped OCR"), .blob(Data())])
        _ = try library.saveImageMarkup(item.id, document: .init())
        XCTAssertTrue(try connection.rows("SELECT item FROM image_analysis").isEmpty)
    }
}
