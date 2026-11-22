import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
let args = CommandLine.arguments
let dir = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])
let scale = Double(args[3])!, delay = Double(args[4])!
let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".png") }.sorted()
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, files.count, nil)!
CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
var last: Data? = nil
var pending: (CGImage, Double)? = nil
func flush() { if let (img, d) = pending { CGImageDestinationAddImage(dest, img, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: d, kCGImagePropertyGIFUnclampedDelayTime: d]] as CFDictionary) } }
for f in files {
    let src = CGImageSourceCreateWithURL(dir.appendingPathComponent(f) as CFURL, nil)!
    let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
    let w = Int(Double(img.width) * scale), h = Int(Double(img.height) * scale)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    let scaled = ctx.makeImage()!
    let bytes = Data(bytes: ctx.data!, count: ctx.bytesPerRow * h)
    if bytes == last, let p = pending { pending = (p.0, p.1 + delay); continue }   // merge identical frames
    flush(); pending = (scaled, delay); last = bytes
}
flush()
// Hold the last frame a little before looping.
print(CGImageDestinationFinalize(dest) ? "ok" : "failed")
