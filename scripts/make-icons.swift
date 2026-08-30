// Generates the AppIcon asset catalog images from one 2048x2048 source:
//  - iOS: full-bleed opaque 1024 (corners flattened onto the icon's own
//    edge color, since iOS applies its own mask)
//  - macOS: the artwork inset to 80% on a transparent canvas, per HIG
// Usage: swift scripts/make-icons.swift <source.png> <AppIcon.appiconset dir>
import AppKit
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else { fatalError("usage: make-icons.swift <source.png> <outdir>") }
let srcURL = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2], isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

guard let dataProvider = CGDataProvider(url: srcURL as CFURL),
      let srcImageSource = CGImageSourceCreateWithDataProvider(dataProvider, nil),
      let src = CGImageSourceCreateImageAtIndex(srcImageSource, 0, nil)
else { fatalError("cannot read \(srcURL.path)") }

// Sample a pixel well inside the artwork near a corner for the flatten color.
func cornerColor(of image: CGImage) -> CGColor {
    let ctx = CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let probe = CGFloat(image.width) * 0.09
    ctx.draw(image, in: CGRect(
        x: -probe, y: -probe,
        width: CGFloat(image.width), height: CGFloat(image.height)))
    let p = ctx.data!.bindMemory(to: UInt8.self, capacity: 4)
    return CGColor(
        srgbRed: CGFloat(p[0]) / 255, green: CGFloat(p[1]) / 255,
        blue: CGFloat(p[2]) / 255, alpha: 1)
}

func write(_ image: CGImage, to name: String) {
    let url = outDir.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("write failed: \(name)") }
    print("wrote \(name) (\(image.width)px)")
}

func render(size: Int, inset: CGFloat, background: CGColor?) -> CGImage {
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    if let background {
        ctx.setFillColor(background)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }
    let content = CGFloat(size) * (1 - inset * 2)
    let origin = (CGFloat(size) - content) / 2
    ctx.draw(src, in: CGRect(x: origin, y: origin, width: content, height: content))
    return ctx.makeImage()!
}

let flat = cornerColor(of: src)
write(render(size: 1024, inset: 0, background: flat), to: "ios-1024.png")
for size in [16, 32, 64, 128, 256, 512, 1024] {
    write(render(size: size, inset: 0.1, background: nil), to: "mac-\(size).png")
}

let contents = """
{
  "images" : [
    { "filename" : "ios-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "filename" : "mac-16.png",   "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "mac-32.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "mac-32.png",   "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "mac-64.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "mac-128.png",  "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "mac-256.png",  "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "mac-256.png",  "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "mac-512.png",  "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "mac-512.png",  "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "mac-1024.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try contents.write(to: outDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote Contents.json")
