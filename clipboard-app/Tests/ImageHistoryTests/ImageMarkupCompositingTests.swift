import AppKit
import ImageIO
import QuartzCore
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class ImageMarkupCompositingTests: HistoryTestCase {
    private func source(width: Int = 160, height: Int = 120, alpha: UInt8 = 255) throws -> NSImage {
        let colors: [[UInt8]] = [[210, 40, 30, alpha], [20, 190, 70, alpha], [30, 70, 220, alpha], [210, 160, 20, alpha]]
        var bytes = Data(count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let data = raw.bindMemory(to: UInt8.self)
            for y in 0..<height { for x in 0..<width {
                let color = colors[(y < height / 2 ? 0 : 2) + (x < width / 2 ? 0 : 1)], at = (y * width + x) * 4
                for component in 0..<4 { data[at + component] = color[component] }
            } }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: bytes as CFData))
        let pixels = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent))
        return NSImage(cgImage: pixels, size: NSSize(width: width, height: height))
    }
    private func context(_ size: NSSize, scale: CGFloat = 1) throws -> CGContext {
        let value = try XCTUnwrap(CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0, space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        value.scaleBy(x: scale, y: scale); return value
    }
    private func pixels(_ value: CGContext) throws -> [UInt8] {
        let data = try XCTUnwrap(value.data)
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: value.bytesPerRow * value.height))
    }
    private func drawReference(_ canvas: ImageMarkupCanvas, into context: CGContext) {
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSBezierPath(rect: canvas.bounds).addClip()
        canvas.image?.draw(in: canvas.imageFrame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                           hints: [.interpolation: NSImageInterpolation.high])
        ImageMarkupRenderer.draw(elements: canvas.document.elements, in: canvas.imageFrame)
    }
    private func displayLayers(_ layer: CALayer) {
        layer.displayIfNeeded(); layer.sublayers?.forEach(displayLayers)
    }
    private func drawComposited(_ canvas: ImageMarkupCanvas, into context: CGContext) throws {
        canvas.layoutSubtreeIfNeeded(); canvas.displayIfNeeded()
        let layer = try XCTUnwrap(canvas.layer); displayLayers(layer)
        CATransaction.flush(); layer.render(in: context)
    }
    private func withCanvas(size: NSSize = NSSize(width: 160, height: 120),
                            _ body: (ImageMarkupCanvas) throws -> Void) rethrows {
        _ = NSApplication.shared
        let canvas = ImageMarkupCanvas(frame: NSRect(origin: .zero, size: size))
        let window = NSWindow(contentRect: canvas.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.close() }; try body(canvas)
    }
    private func mouse(_ type: NSEvent.EventType, point: NSPoint, canvas: ImageMarkupCanvas) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: canvas.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    private var marks: [ImageMarkupElement] { [
        .init(tool: .line, points: [.init(x: 0.1, y: 0.2), .init(x: 0.8, y: 0.7)], color: .white, lineWidth: 0.02),
        .init(tool: .rectangle, points: [.init(x: 0.2, y: 0.35), .init(x: 0.4, y: 0.6)], color: .purple, lineWidth: 0.03, fill: true),
        .init(tool: .marker, points: [.init(x: 0.1, y: 0.8), .init(x: 0.45, y: 0.85), .init(x: 0.9, y: 0.8)], color: .yellow, lineWidth: 0.08)
    ] }

    func testCompositedCroppedPixelsMatchAtOneAndTwoBackingPixelsPerPoint() throws {
        for scale in [CGFloat(1), 2] {
            try withCanvas { canvas in
                // One source pixel per output pixel isolates coordinate/alpha
                // equivalence from the two renderers' resampling kernels.
                canvas.image = try source(width: Int(320 * scale), height: Int(240 * scale), alpha: 192)
                canvas.load(.init(elements: marks, crop: .init(x: 0.25, y: 0.25, width: 0.5, height: 0.5)))
                let reference = try context(canvas.bounds.size, scale: scale), composed = try context(canvas.bounds.size, scale: scale)
                drawReference(canvas, into: reference); try drawComposited(canvas, into: composed)
                let differences = try zip(pixels(reference), pixels(composed)).map { abs(Int($0) - Int($1)) }
                XCTAssertLessThanOrEqual(differences.max() ?? 0, 2, "Crop clipping and native backing coordinates must preserve the previous rendered output")
            }
        }
    }

    func testCompositedPixelsKeepImageOrientationAlphaAndVectorPlacement() throws {
        for alpha: UInt8 in [255, 128] {
            try withCanvas { canvas in
                canvas.image = try source(alpha: alpha); canvas.load(.init(elements: marks))
                let reference = try context(canvas.bounds.size), composed = try context(canvas.bounds.size)
                drawReference(canvas, into: reference); try drawComposited(canvas, into: composed)
                let expected = try pixels(reference), actual = try pixels(composed)
                let differences = zip(expected, actual).map { abs(Int($0) - Int($1)) }
                XCTAssertLessThanOrEqual(differences.max() ?? 0, 2, "Orientation, alpha and vector geometry must match the previous renderer")
            }
        }
        if ProcessInfo.processInfo.environment["CLIPBOARDLINE_MARKUP_BENCHMARK"] == "1" { try benchmarkRetainedBase() }
    }

    func testActiveCropOverlayDimsOnlyOutsideTheSelection() throws {
        try withCanvas { canvas in
            canvas.image = try source()
            let original = try context(canvas.bounds.size); drawReference(canvas, into: original)
            canvas.beginCrop()
            canvas.mouseDown(with: mouse(.leftMouseDown, point: NSPoint(x: 30, y: 30), canvas: canvas))
            canvas.mouseDragged(with: mouse(.leftMouseDragged, point: NSPoint(x: 130, y: 90), canvas: canvas))
            canvas.mouseUp(with: mouse(.leftMouseUp, point: NSPoint(x: 130, y: 90), canvas: canvas))
            let composed = try context(canvas.bounds.size); try drawComposited(canvas, into: composed)
            let expected = try pixels(original), actual = try pixels(composed)
            let inside = 58 * composed.bytesPerRow + 78 * 4, outside = 5 * composed.bytesPerRow + 5 * 4
            for component in 0..<3 {
                XCTAssertEqual(Double(actual[inside + component]), Double(expected[inside + component]), accuracy: 2)
                XCTAssertEqual(Double(actual[outside + component]), Double(expected[outside + component]) * 0.45, accuracy: 2)
            }
            XCTAssertEqual(actual[outside + 3], 255)
            canvas.cancelCrop()
        }
    }

    func testCompositingDoesNotRetainAClosedDocument() throws {
        _ = NSApplication.shared
        weak var released: ImageMarkupCanvas?
        try autoreleasepool {
            let canvas = ImageMarkupCanvas(frame: NSRect(x: 0, y: 0, width: 160, height: 120))
            canvas.image = try source(width: 640, height: 480); released = canvas
            XCTAssertNotNil(released)
        }
        XCTAssertNil(released, "The permanent overlay callback must not keep its large base image/document alive")
    }

    func testOverlayLeavesPointerAndNativeTextEditingWithTheDocument() throws {
        try withCanvas { canvas in
            canvas.image = try source(); canvas.isMarkupEditing = true
            XCTAssertTrue(canvas.hitTest(NSPoint(x: 60, y: 40)) === canvas)
            canvas.setTool(.text)
            canvas.mouseDown(with: mouse(.leftMouseDown, point: NSPoint(x: 30, y: 30), canvas: canvas))
            let editor = try XCTUnwrap(canvas.textEditor)
            XCTAssertFalse(canvas.hitTest(NSPoint(x: 40, y: 40)) === canvas)
            editor.string = "İstanbul ✓"
            XCTAssertTrue(canvas.finishTextEditing())
            XCTAssertEqual(canvas.document.elements.first?.text, "İstanbul ✓")
            XCTAssertTrue(canvas.hitTest(NSPoint(x: 60, y: 40)) === canvas)
        }
    }

    private func benchmarkRetainedBase() throws {
        var results = [[String: Any]]()
        for (width, height) in [(3840, 2160), (7680, 4320)] {
            try autoreleasepool {
                let fixture = try SyntheticFixture(); defer { fixture.cleanup() }
                let original = try source(width: width, height: height)
                let originalPixels = try XCTUnwrap(original.cgImage(forProposedRect: nil, context: nil, hints: nil))
                let file = try fixture.image(name: "synthetic-markup-\(width).png")
                let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil))
                CGImageDestinationAddImage(destination, originalPixels, nil)
                XCTAssertTrue(CGImageDestinationFinalize(destination))
                // Match ImagePreview's real bounded decode before timing warm
                // redraws. An 8K source is not an 8K preview texture.
                let image = try XCTUnwrap(makeThumbnail(file, maxPixels: 4000))
                try withCanvas(size: NSSize(width: 960, height: 540)) { canvas in
                    canvas.image = image; canvas.load(.init(elements: marks))
                    let target = try context(canvas.bounds.size, scale: 2)
                    let overlay = try XCTUnwrap(canvas.subviews.first)
                    let graphics = NSGraphicsContext(cgContext: target, flipped: false)
                    // Warm both routes. The retained source has already been
                    // prepared once, as it would be before the next pointer event.
                    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
                    defer { NSGraphicsContext.restoreGraphicsState() }
                    drawReference(canvas, into: target); overlay.draw(overlay.bounds)
                    var before = [Double](), after = [Double]()
                    for sample in 0..<6 {
                        for retained in (sample.isMultiple(of: 2) ? [false, true] : [true, false]) {
                            let start = CACurrentMediaTime()
                            for _ in 0..<32 {
                                target.clear(CGRect(origin: .zero, size: canvas.bounds.size))
                                if retained { overlay.draw(overlay.bounds) } else { drawReference(canvas, into: target) }
                            }
                            let milliseconds = (CACurrentMediaTime() - start) * 1000 / 32
                            if retained { after.append(milliseconds) } else { before.append(milliseconds) }
                        }
                    }
                    results.append(["sourceWidth": width, "sourceHeight": height,
                        "decodedWidth": Int(image.size.width), "decodedHeight": Int(image.size.height),
                        "displayPoints": [960, 540], "backingScale": 2, "drawsPerSample": 32,
                        "baselineMillisecondsPerDraw": before, "retainedMillisecondsPerDraw": after])
                }
            }
        }
#if DEBUG
        let configuration = "debug"
#else
        let configuration = "release"
#endif
        let report: [String: Any] = ["benchmark": "retained-markup-base", "configuration": configuration,
            "scope": "Warm main-thread image/vector raster CPU microbenchmark. GPU compositing is not measured; this is not display FPS, native gesture latency or a release acceptance substitute.", "results": results]
        let json = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        print("CLIPBOARDLINE_MARKUP_BENCHMARK " + String(decoding: json, as: UTF8.self))
    }

#if DEBUG || STANDALONE_TESTS
    func testReplacingOrClearingSourceUpdatesTheRetainedBaseExactlyOnce() throws {
        try withCanvas { canvas in
            canvas.image = try source(); let original = try XCTUnwrap(canvas.retainedBaseImageForTesting), count = canvas.baseImagePreparationCount
            canvas.image = try source(width: 200, height: 140, alpha: 128)
            XCTAssertFalse(canvas.retainedBaseImageForTesting === original)
            XCTAssertEqual(canvas.baseImagePreparationCount, count + 1)
            canvas.image = nil; canvas.load(.init())
            XCTAssertNil(canvas.retainedBaseImageForTesting)
            let composed = try context(canvas.bounds.size); try drawComposited(canvas, into: composed)
            XCTAssertTrue(try pixels(composed).allSatisfy { $0 == 0 }, "The prior image must not survive source clearing")
        }
    }

    func testDrawingAndCroppingKeepOnePreparedBaseImage() throws {
        try withCanvas { canvas in
            canvas.image = try source(width: 640, height: 480)
            let base = try XCTUnwrap(canvas.retainedBaseImageForTesting), preparations = canvas.baseImagePreparationCount, geometry = canvas.baseImageGeometryCount
            canvas.isMarkupEditing = true; canvas.setTool(.marker)
            canvas.mouseDown(with: mouse(.leftMouseDown, point: NSPoint(x: 10, y: 20), canvas: canvas))
            for x in stride(from: 12, through: 140, by: 2) {
                canvas.mouseDragged(with: mouse(.leftMouseDragged, point: NSPoint(x: x, y: 40), canvas: canvas))
                let output = try context(canvas.bounds.size); try drawComposited(canvas, into: output)
            }
            canvas.mouseUp(with: mouse(.leftMouseUp, point: NSPoint(x: 140, y: 40), canvas: canvas))
            canvas.beginCrop()
            canvas.mouseDown(with: mouse(.leftMouseDown, point: NSPoint(x: 30, y: 30), canvas: canvas))
            for x in stride(from: 60, through: 140, by: 2) {
                canvas.mouseDragged(with: mouse(.leftMouseDragged, point: NSPoint(x: x, y: 90), canvas: canvas))
                let output = try context(canvas.bounds.size); try drawComposited(canvas, into: output)
            }
            XCTAssertEqual(canvas.baseImagePreparationCount, preparations)
            XCTAssertEqual(canvas.baseImageGeometryCount, geometry, "Drawing/crop selection must not rewrite unchanged base geometry")
            XCTAssertTrue(canvas.retainedBaseImageForTesting === base)
            XCTAssertTrue(canvas.retainedBaseLayerForTesting.contents as AnyObject? === base)
            XCTAssertGreaterThan(canvas.overlayDrawCount, 20)
            XCTAssertEqual(canvas.document.elements.count, 1)
            XCTAssertGreaterThan(canvas.document.elements[0].points.count, 50, "Draw coalescing must not discard pen/marker samples")
            canvas.cancelCrop(); canvas.cancelGesture()
        }
    }

    func testCropUndoResizeAndBackingGeometryDoNotAllocateAnotherBase() throws {
        try withCanvas { canvas in
            canvas.image = try source(); let count = canvas.baseImagePreparationCount
            let original = try XCTUnwrap(canvas.retainedBaseImageForTesting)
            let document = ImageMarkupDocument(elements: marks, crop: .init(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
            canvas.load(document)
            XCTAssertEqual(canvas.retainedBaseLayerForTesting.frame, canvas.imageFrame)
            XCTAssertEqual(canvas.retainedBaseLayerForTesting.contentsScale, canvas.window?.backingScaleFactor)
            let frame = canvas.imageFrame
            canvas.beginCrop(); XCTAssertEqual(canvas.retainedBaseLayerForTesting.frame, canvas.bounds)
            canvas.cancelCrop(); XCTAssertEqual(canvas.retainedBaseLayerForTesting.frame, frame)
            canvas.setFrameSize(NSSize(width: 400, height: 300)); canvas.layoutSubtreeIfNeeded()
            XCTAssertEqual(canvas.retainedBaseLayerForTesting.frame, canvas.imageFrame)
            XCTAssertTrue(canvas.retainedBaseImageForTesting === original)
            XCTAssertEqual(canvas.baseImagePreparationCount, count)
            XCTAssertTrue(canvas.layer?.masksToBounds == true)
            canvas.load(.init(crop: .init(x: 0.495, y: 0.495, width: 0.01, height: 0.01)))
            XCTAssertEqual(canvas.retainedBaseImageForTesting?.width, 160)
            XCTAssertEqual(canvas.retainedBaseLayerForTesting.frame.width, 40_000, accuracy: 0.0001)
            XCTAssertEqual(canvas.baseImagePreparationCount, count)
        }
    }
#endif
}
