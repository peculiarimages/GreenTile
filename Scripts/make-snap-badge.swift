#!/usr/bin/env swift
// Builds the snap-back badge from the app icon's source artwork, at the artwork's own size, so the
// badge stays sharp when it is shown large.
//
//   swift Scripts/make-snap-badge.swift Artwork/AppIconSource.webp GreenTile/Assets.xcassets/SnapBadge.imageset
//
// The artwork is clipped to the same rounded square ("squircle") as the app icon, with no margin
// and no shadow (the badge view adds its own), and written as snap-badge.png with its Contents.json.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("usage: swift make-snap-badge.swift <square source image> <output .imageset folder>\n", stderr)
    exit(1)
}
guard let source = NSImage(contentsOf: URL(fileURLWithPath: arguments[1])),
      let artwork = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
      artwork.width == artwork.height else {
    fputs("could not read a square image from \(arguments[1])\n", stderr)
    exit(1)
}
let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
let side = artwork.width
let rect = CGRect(x: 0, y: 0, width: side, height: side)

/// The same superellipse the app icon uses.
func squircle(in rect: CGRect, exponent n: Double = 5) -> CGPath {
    let path = CGMutablePath()
    let a = Double(rect.width) / 2, b = Double(rect.height) / 2
    let cx = Double(rect.midX), cy = Double(rect.midY)
    let steps = 1440
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * Double.pi
        let c = cos(t), s = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high
ctx.addPath(squircle(in: rect))
ctx.clip()
ctx.draw(artwork, in: rect)

try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
try! png.write(to: output.appendingPathComponent("snap-badge.png"))
try! """
{
  "images" : [
    { "idiom" : "universal", "filename" : "snap-badge.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

""".write(to: output.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote \(side) x \(side) badge to \(output.path)")
