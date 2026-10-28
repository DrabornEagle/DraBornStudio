// Original local-review artwork; does not use Tendedero's reserved icon.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.setFillColor(CGColor(red: 0.07, green: 0.13, blue: 0.20, alpha: 1))
context.addPath(CGPath(roundedRect: CGRect(x: 50, y: 50, width: 924, height: 924),
    cornerWidth: 180, cornerHeight: 180, transform: nil))
context.fillPath()
context.setFillColor(CGColor(red: 0.95, green: 0.98, blue: 1, alpha: 1))
context.fill(CGRect(x: 270, y: 190, width: 484, height: 604))
context.setFillColor(CGColor(red: 0.12, green: 0.72, blue: 0.82, alpha: 1))
context.fill(CGRect(x: 360, y: 724, width: 304, height: 116))
context.setStrokeColor(CGColor(red: 0.12, green: 0.72, blue: 0.82, alpha: 1))
context.setLineWidth(24)
for y in [350, 460, 570] {
    context.move(to: CGPoint(x: 350, y: y))
    context.addLine(to: CGPoint(x: 674, y: y))
}
context.strokePath()
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
