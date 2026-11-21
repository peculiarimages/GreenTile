#!/usr/bin/env swift
// Builds the macOS app icon set from a square source image.
//
//   swift Scripts/make-app-icon.swift Artwork/AppIconSource.webp GreenTile/Assets.xcassets/AppIcon.appiconset
//
// The artwork is placed the way Apple's macOS icon template does it: on a 1024 x 1024 canvas, a
// rounded-square ("squircle") body 824 points wide, centred, with a soft drop shadow beneath and
// transparent margins around it. Every size the asset catalog needs is then scaled down from that
// master, and Contents.json is written next to them. A 256 px preview for the README is written
// beside the source image.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("usage: swift make-app-icon.swift <square source image> <output .appiconset folder>\n", stderr)
    exit(1)
}
let sourceURL = URL(fileURLWithPath: arguments[1])
let outputDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)

guard let sourceImage = NSImage(contentsOf: sourceURL),
      let artwork = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("could not read \(sourceURL.path)\n", stderr)
    exit(1)
}
guard artwork.width == artwork.height else {
    fputs("the source image must be square (it is \(artwork.width) x \(artwork.height))\n", stderr)
    exit(1)
}

let canvas: CGFloat = 1024
let body: CGFloat = 824                      // the icon body inside the canvas
let bodyRect = CGRect(x: (canvas - body) / 2, y: (canvas - body) / 2, width: body, height: body)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

/// A superellipse, which is close to the continuous-corner rounded square macOS icons use.
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

func makeContext(side: Int) -> CGContext {
    CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

// MARK: Master (1024 x 1024)

let master: CGImage = {
    let ctx = makeContext(side: Int(canvas))
    ctx.interpolationQuality = .high
    let shape = squircle(in: bodyRect)

    // Soft shadow under the body (cast by an otherwise invisible fill).
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24,
                  color: CGColor(colorSpace: colorSpace, components: [0, 0, 0, 0.32])!)
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [0, 0, 0, 1])!)
    ctx.fillPath()
    ctx.restoreGState()

    // The artwork, clipped to the body.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.draw(artwork, in: bodyRect)
    ctx.restoreGState()
    return ctx.makeImage()!
}()

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { fputs("PNG encoding failed\n", stderr); exit(1) }
    try! data.write(to: url)
}

func scaled(_ image: CGImage, to side: Int) -> CGImage {
    if side == Int(canvas) { return image }
    let ctx = makeContext(side: side)
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    return ctx.makeImage()!
}

// MARK: Asset catalog

try! FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let sizes: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                                          (256, 1), (256, 2), (512, 1), (512, 2)]
var entries: [String] = []
for (points, scale) in sizes {
    let pixels = points * scale
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    writePNG(scaled(master, to: pixels), to: outputDirectory.appendingPathComponent(name))
    entries.append("""
        { "idiom" : "mac", "scale" : "\(scale)x", "size" : "\(points)x\(points)", "filename" : "\(name)" }
    """)
}
let contents = """
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

"""
try! contents.write(to: outputDirectory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
// A 256 px picture of the finished icon, kept next to the source artwork, for the README.
writePNG(scaled(master, to: 256), to: sourceURL.deletingLastPathComponent().appendingPathComponent("AppIconPreview.png"))
print("wrote \(sizes.count) icon sizes and Contents.json to \(outputDirectory.path), and AppIconPreview.png")
