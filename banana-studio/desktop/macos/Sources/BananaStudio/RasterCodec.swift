import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

struct RasterData {
    let pixels: Data
    let width: Int
    let height: Int
}
enum RasterCodec {
    static let maximumPixels = 33_554_432
    static let space = CGColorSpace(name: CGColorSpace.sRGB)!
    enum Failure: Error { case invalidImage, invalidSize, encodingFailed }
    static func dimensions(_ width: Int, _ height: Int) throws {
        guard width > 0, height > 0, width <= maximumPixels, height <= maximumPixels, width <= maximumPixels / height else { throw Failure.invalidSize }
    }
    static func decode(_ data: Data) throws -> RasterData {
        guard data.count <= 50 * 1024 * 1024, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = properties[kCGImagePropertyPixelWidth] as? Int, let h = properties[kCGImagePropertyPixelHeight] as? Int else { throw Failure.invalidImage }
        try dimensions(w, h)
        guard let original = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Failure.invalidImage }
        let orientation = (properties[kCGImagePropertyOrientation] as? Int32) ?? 1
        let oriented = CIImage(cgImage: original).oriented(forExifOrientation: orientation)
        let context = CIContext(options: [.workingColorSpace: space, .outputColorSpace: space])
        guard let image = context.createCGImage(oriented, from: oriented.extent, format: .RGBA8, colorSpace: space) else { throw Failure.invalidImage }
        let width = image.width, height = image.height
        var pixels = Data(count: width * height * 4)
        let succeeded = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let bitmap = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            bitmap.setBlendMode(.copy); bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
        }
        guard succeeded else { throw Failure.invalidImage }
        // The shared compositor uses straight RGBA, matching the web server.
        pixels.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            let bytes = buffer.bindMemory(to: UInt8.self)
            for i in stride(from: 0, to: bytes.count, by: 4) {
                let alpha = Int(bytes[i + 3]); if alpha > 0 && alpha < 255 { for c in 0..<3 { bytes[i + c] = UInt8(min(255, (Int(bytes[i + c]) * 255 + alpha / 2) / alpha)) } }
            }
        }
        return RasterData(pixels: pixels, width: width, height: height)
    }
    static func encode(_ raster: RasterData) throws -> Data {
        try dimensions(raster.width, raster.height)
        guard raster.pixels.count == raster.width * raster.height * 4 else { throw Failure.invalidSize }
        guard let provider = CGDataProvider(data: raster.pixels as CFData), let image = CGImage(width: raster.width, height: raster.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: raster.width * 4, space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw Failure.encodingFailed }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw Failure.encodingFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encodingFailed }; return output as Data
    }
    static func run() -> Int32 {
        do {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            guard input.count < 200 * 1024 * 1024, let request = try JSONSerialization.jsonObject(with: input) as? [String: Any], let operation = request["operation"] as? String, let encoded = request["data"] as? String, let bytes = Data(base64Encoded: encoded) else { return 1 }
            let result: [String: Any]
            if operation == "decode" {
                let raster = try decode(bytes); result = ["data": raster.pixels.base64EncodedString(), "width": raster.width, "height": raster.height]
            } else if operation == "encode", let width = request["width"] as? Int, let height = request["height"] as? Int {
                result = ["data": try encode(RasterData(pixels: bytes, width: width, height: height)).base64EncodedString()]
            } else { return 1 }
            try FileHandle.standardOutput.write(contentsOf: JSONSerialization.data(withJSONObject: result)); return 0
        } catch { return 1 }
    }
}
