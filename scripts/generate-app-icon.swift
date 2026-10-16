import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Package the approved imagegen artwork; keep the original source for reproducibility.
// The operating system applies the outer icon mask. This script only scales to the catalog size.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let sourceURL = root.appendingPathComponent("docs/app-icon-2026-10-08/source.png")
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil),
      artwork.width == artwork.height else {
    fatalError("Missing or non-square app icon source: \(sourceURL.path)")
}
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.interpolationQuality = .high
context.draw(artwork, in: CGRect(x: 0, y: 0, width: size, height: size))
let output = root.appendingPathComponent("ios-app/Yuji/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination))
print(output.path)
