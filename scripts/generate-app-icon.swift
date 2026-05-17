#!/usr/bin/env swift

import AppKit
import Foundation

let projectDirectory: URL
if CommandLine.arguments.count > 1 {
    projectDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
} else {
    projectDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
}

let assetsDirectory = projectDirectory.appendingPathComponent("Assets", isDirectory: true)
let iconsetDirectory = assetsDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let iconURL = assetsDirectory.appendingPathComponent("MutePls.icns")

try FileManager.default.createDirectory(at: iconsetDirectory, withIntermediateDirectories: true)

let iconFiles: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for iconFile in iconFiles {
    let image = drawIcon(size: iconFile.pixels)
    let destination = iconsetDirectory.appendingPathComponent(iconFile.name)
    try writePNG(image, to: destination)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c",
    "icns",
    iconsetDirectory.path,
    "-o",
    iconURL.path
]

try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw IconGenerationError.iconutilFailed(process.terminationStatus)
}

print("Generated \(iconURL.path)")

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    let scale = size / 1024.0

    image.lockFocus()
    defer { image.unlockFocus() }

    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    canvas.fill()

    let cornerRadius = 224.0 * scale
    let background = NSBezierPath(roundedRect: canvas.insetBy(dx: 56 * scale, dy: 56 * scale), xRadius: cornerRadius, yRadius: cornerRadius)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.15, alpha: 1.0),
        NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.04, alpha: 1.0)
    ])
    gradient?.draw(in: background, angle: 315)

    let rim = NSBezierPath(roundedRect: canvas.insetBy(dx: 78 * scale, dy: 78 * scale), xRadius: 196 * scale, yRadius: 196 * scale)
    NSColor(calibratedWhite: 1.0, alpha: 0.12).setStroke()
    rim.lineWidth = 14 * scale
    rim.stroke()

    let micRect = NSRect(x: 382 * scale, y: 392 * scale, width: 260 * scale, height: 356 * scale)
    let micBody = NSBezierPath(roundedRect: micRect, xRadius: 130 * scale, yRadius: 130 * scale)
    NSColor(calibratedWhite: 0.96, alpha: 1.0).setFill()
    micBody.fill()

    let innerRect = micRect.insetBy(dx: 64 * scale, dy: 64 * scale)
    let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: 64 * scale, yRadius: 64 * scale)
    NSColor(calibratedWhite: 0.18, alpha: 1.0).setFill()
    innerPath.fill()

    let stem = NSBezierPath()
    stem.lineWidth = 54 * scale
    stem.lineCapStyle = .round
    stem.lineJoinStyle = .round
    NSColor(calibratedWhite: 0.96, alpha: 1.0).setStroke()
    stem.move(to: NSPoint(x: 512 * scale, y: 286 * scale))
    stem.line(to: NSPoint(x: 512 * scale, y: 210 * scale))
    stem.move(to: NSPoint(x: 396 * scale, y: 210 * scale))
    stem.line(to: NSPoint(x: 628 * scale, y: 210 * scale))
    stem.stroke()

    let cradle = NSBezierPath()
    cradle.lineWidth = 54 * scale
    cradle.lineCapStyle = .round
    cradle.move(to: NSPoint(x: 286 * scale, y: 512 * scale))
    cradle.curve(
        to: NSPoint(x: 738 * scale, y: 512 * scale),
        controlPoint1: NSPoint(x: 286 * scale, y: 300 * scale),
        controlPoint2: NSPoint(x: 738 * scale, y: 300 * scale)
    )
    cradle.stroke()

    let slash = NSBezierPath()
    slash.lineWidth = 68 * scale
    slash.lineCapStyle = .round
    NSColor.systemRed.setStroke()
    slash.move(to: NSPoint(x: 304 * scale, y: 266 * scale))
    slash.line(to: NSPoint(x: 738 * scale, y: 758 * scale))
    slash.stroke()

    let greenDot = NSBezierPath(ovalIn: NSRect(x: 676 * scale, y: 184 * scale, width: 132 * scale, height: 132 * scale))
    NSColor.systemGreen.setFill()
    greenDot.fill()

    let redDot = NSBezierPath(ovalIn: NSRect(x: 792 * scale, y: 184 * scale, width: 132 * scale, height: 132 * scale))
    NSColor.systemRed.setFill()
    redDot.fill()

    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw IconGenerationError.pngEncodingFailed(url.path)
    }

    try png.write(to: url, options: .atomic)
}

enum IconGenerationError: Error, CustomStringConvertible {
    case pngEncodingFailed(String)
    case iconutilFailed(Int32)

    var description: String {
        switch self {
        case let .pngEncodingFailed(path):
            return "Could not encode PNG at \(path)"
        case let .iconutilFailed(status):
            return "iconutil failed with status \(status)"
        }
    }
}
