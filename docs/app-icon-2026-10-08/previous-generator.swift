import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Original, deterministic ledger mark. iOS applies the outer icon mask.
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let green = CGColor(red: 0.208, green: 0.471, blue: 0.369, alpha: 1)
func fill(_ rect: CGRect, radius: CGFloat) {
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()
}
context.setFillColor(green)
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.setFillColor(CGColor(red: 0.976, green: 0.973, blue: 0.949, alpha: 1))
fill(CGRect(x: 254, y: 202, width: 516, height: 620), radius: 76)
context.setFillColor(green)
for rect in [CGRect(x: 352, y: 270, width: 16, height: 484),
             CGRect(x: 424, y: 597, width: 240, height: 28),
             CGRect(x: 424, y: 473, width: 186, height: 28)] {
    fill(rect, radius: 8)
}
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = root.appendingPathComponent("ios-app/Yuji/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination))
print(output.path)
