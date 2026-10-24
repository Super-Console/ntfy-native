import AppKit
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appendingPathComponent("Assets", isDirectory: true)
let build = root.appendingPathComponent(".build", isDirectory: true)
let sourceURL = assets.appendingPathComponent("green-glass-chat-terminal-icon.png")
let iconset = build.appendingPathComponent("ntfy-native.iconset", isDirectory: true)

guard let input = NSBitmapImageRep(data: try Data(contentsOf: sourceURL)) else {
    fatalError("Could not load user-provided app icon at \(sourceURL.path)")
}
// Remove only the exterior white matte. Never key out the white terminal
// glyph or the glass highlights enclosed by the green silhouette.
var spans: [(Int, Int)] = []
var minX = input.pixelsWide, minY = input.pixelsHigh, maxX = 0, maxY = 0
for y in 0..<input.pixelsHigh {
    var left = input.pixelsWide, right = -1
    for x in 0..<input.pixelsWide {
        guard let c = input.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        if max(c.greenComponent, c.blueComponent) - c.redComponent > 0.07 {
            left = min(left, x)
            right = max(right, x)
        }
    }
    spans.append((left, right))
    if right >= left {
        minX = min(minX, left); maxX = max(maxX, right)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}
guard maxX > minX, maxY > minY else { fatalError("No green icon silhouette found") }
let side = max(maxX - minX + 1, maxY - minY + 1)
let originX = (minX + maxX + 1 - side) / 2
let originY = (minY + maxY + 1 - side) / 2
let cleaned = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let transparent = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0)
for y in 0..<side {
    let sy = originY + y
    for x in 0..<side {
        let sx = originX + x
        if sy >= 0, sy < spans.count, sx >= spans[sy].0, sx <= spans[sy].1,
           let color = input.colorAt(x: sx, y: sy) {
            cleaned.setColor(color, atX: x, y: y)
        } else {
            cleaned.setColor(transparent, atX: x, y: y)
        }
    }
}
let master = build.appendingPathComponent("AppIcon-clean.png")
try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
try cleaned.representation(using: .png, properties: [:])!.write(to: master, options: .atomic)
let source = NSImage(data: cleaned.representation(using: .png, properties: [:])!)!
let sourceRect = NSRect(origin: .zero, size: source.size)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, size) in sizes {
    let destination = iconset.appendingPathComponent(name)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not allocate bitmap for \(name)")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.imageInterpolation = .high
    source.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: sourceRect,
        operation: .copy,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode \(name)")
    }
    try png.write(to: destination, options: .atomic)
}

print("Rendered macOS iconset from \(sourceURL.path)")

// Notification Center also resolves icons through the compiled asset catalog.
let catalog = build.appendingPathComponent("AppIconAssets.xcassets", isDirectory: true)
let appIcon = catalog.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: appIcon, withIntermediateDirectories: true)
let info: [String: Any] = ["author": "xcode", "version": 1]
var images: [[String: String]] = []
for (name, pixels) in sizes {
    let scale = name.contains("@2x") ? 2 : 1
    let points = pixels / scale
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    try Data(contentsOf: iconset.appendingPathComponent(name)).write(to: appIcon.appendingPathComponent(name), options: .atomic)
}
try JSONSerialization.data(withJSONObject: ["info": info], options: [.prettyPrinted, .sortedKeys])
    .write(to: catalog.appendingPathComponent("Contents.json"), options: .atomic)
try JSONSerialization.data(withJSONObject: ["images": images, "info": info], options: [.prettyPrinted, .sortedKeys])
    .write(to: appIcon.appendingPathComponent("Contents.json"), options: .atomic)
