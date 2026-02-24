import AppKit
import Foundation

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    NSGraphicsContext.current?.imageInterpolation = .high

    let fullRect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.22

    let bgPath = roundedRect(fullRect.insetBy(dx: size * 0.02, dy: size * 0.02), radius: radius)
    let bgGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.13, alpha: 1.0),
        NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.05, alpha: 1.0)
    ])!
    bgGradient.draw(in: bgPath, angle: -90)

    // Stronger boundary for dark backgrounds (Dock/menu bar in dark mode).
    NSColor(calibratedRed: 1.00, green: 0.34, blue: 0.32, alpha: 0.95).setStroke()
    bgPath.lineWidth = size * 0.018
    bgPath.stroke()

    let innerOutline = roundedRect(fullRect.insetBy(dx: size * 0.032, dy: size * 0.032), radius: radius * 0.92)
    NSColor(calibratedWhite: 1.0, alpha: 0.20).setStroke()
    innerOutline.lineWidth = size * 0.006
    innerOutline.stroke()

    // Soft highlight bubble.
    NSColor(calibratedWhite: 1.0, alpha: 0.08).setFill()
    roundedRect(NSRect(x: size * 0.12, y: size * 0.60, width: size * 0.76, height: size * 0.28), radius: size * 0.14).fill()

    // Book shape.
    let bookRect = NSRect(x: size * 0.20, y: size * 0.22, width: size * 0.60, height: size * 0.58)
    let bookPath = roundedRect(bookRect, radius: size * 0.08)
    NSColor(calibratedRed: 0.99, green: 0.99, blue: 0.99, alpha: 1.0).setFill()
    bookPath.fill()

    NSColor(calibratedRed: 1.00, green: 0.30, blue: 0.30, alpha: 1.0).setStroke()
    bookPath.lineWidth = size * 0.028
    bookPath.stroke()

    // Spine and page split.
    NSColor(calibratedRed: 1.00, green: 0.47, blue: 0.38, alpha: 1.0).setFill()
    roundedRect(NSRect(x: size * 0.48, y: size * 0.24, width: size * 0.04, height: size * 0.54), radius: size * 0.02).fill()

    // Eyes.
    let eyeColor = NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.12, alpha: 1.0)
    eyeColor.setFill()
    NSBezierPath(ovalIn: NSRect(x: size * 0.34, y: size * 0.49, width: size * 0.07, height: size * 0.10)).fill()
    NSBezierPath(ovalIn: NSRect(x: size * 0.59, y: size * 0.49, width: size * 0.07, height: size * 0.10)).fill()

    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: size * 0.365, y: size * 0.54, width: size * 0.02, height: size * 0.03)).fill()
    NSBezierPath(ovalIn: NSRect(x: size * 0.615, y: size * 0.54, width: size * 0.02, height: size * 0.03)).fill()

    // Smile.
    eyeColor.setStroke()
    let smile = NSBezierPath()
    smile.lineWidth = size * 0.02
    smile.lineCapStyle = .round
    smile.move(to: NSPoint(x: size * 0.40, y: size * 0.39))
    smile.curve(to: NSPoint(x: size * 0.60, y: size * 0.39), controlPoint1: NSPoint(x: size * 0.46, y: size * 0.31), controlPoint2: NSPoint(x: size * 0.54, y: size * 0.31))
    smile.stroke()

    // Blush.
    NSColor(calibratedRed: 1.00, green: 0.25, blue: 0.32, alpha: 0.48).setFill()
    NSBezierPath(ovalIn: NSRect(x: size * 0.28, y: size * 0.39, width: size * 0.08, height: size * 0.05)).fill()
    NSBezierPath(ovalIn: NSRect(x: size * 0.64, y: size * 0.39, width: size * 0.08, height: size * 0.05)).fill()

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGeneration", code: 1)
    }
    try data.write(to: url)
}

func enforceSize(url: URL, pixels: Int) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = ["-z", "\(pixels)", "\(pixels)", url.path]
    try? process.run()
    process.waitUntilExit()
}

let base = drawIcon(size: 1024)
let baseURL = outDir.appendingPathComponent("icon_512x512@2x.png")
try savePNG(base, to: baseURL)
enforceSize(url: baseURL, pixels: 1024)

let outputs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512)
]

for (name, px) in outputs {
    let img = NSImage(size: NSSize(width: px, height: px))
    img.lockFocus()
    base.draw(in: NSRect(x: 0, y: 0, width: px, height: px), from: NSRect(x: 0, y: 0, width: 1024, height: 1024), operation: .copy, fraction: 1.0)
    img.unlockFocus()
    try savePNG(img, to: outDir.appendingPathComponent(name))
    enforceSize(url: outDir.appendingPathComponent(name), pixels: px)
}

print("Generated app icon set at: \(outDir.path)")
