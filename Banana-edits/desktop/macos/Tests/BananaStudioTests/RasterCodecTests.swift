import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import BananaStudio

final class RasterCodecTests: XCTestCase {
    func testOpaquePixelsAndTopLeftCoordinatesSurvivePNGEncoding() throws {
        let pixels = Data([255,0,0,255, 0,255,0,255, 0,0,255,255, 255,255,0,255])
        let png = try RasterCodec.encode(RasterData(pixels: pixels, width: 2, height: 2))
        let result = try RasterCodec.decode(png)
        XCTAssertEqual(result.width, 2); XCTAssertEqual(result.height, 2)
        XCTAssertEqual(result.pixels, pixels)
    }
    func testEXIFOrientationUsesTheDisplayedCanvas() throws {
        let pixels = Data([255,0,0,255, 0,255,0,255, 0,0,255,255, 255,255,0,255, 0,255,255,255, 255,0,255,255])
        let png = try RasterCodec.encode(RasterData(pixels: pixels, width: 2, height: 3))
        let source = CGImageSourceCreateWithData(png as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let tiff = NSMutableData(), destination = CGImageDestinationCreateWithData(tiff, UTType.tiff.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let result = try RasterCodec.decode(tiff as Data)
        XCTAssertEqual(result.width, 3); XCTAssertEqual(result.height, 2)
        XCTAssertEqual(result.pixels, Data([0,255,255,255, 0,0,255,255, 255,0,0,255, 255,0,255,255, 255,255,0,255, 0,255,0,255]))
    }
    func testMalformedImagesAndOversizedCanvasesAreRejected() {
        XCTAssertThrowsError(try RasterCodec.decode(Data("not an image".utf8)))
        XCTAssertThrowsError(try RasterCodec.encode(RasterData(pixels: Data(), width: 100_000, height: 100_000)))
    }
}
