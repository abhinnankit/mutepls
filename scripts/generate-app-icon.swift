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

if FileManager.default.fileExists(atPath: iconsetDirectory.path) {
    try FileManager.default.removeItem(at: iconsetDirectory)
}

try FileManager.default.createDirectory(at: iconsetDirectory, withIntermediateDirectories: true)

let iconFiles: [IconFile] = [
    IconFile(pointSize: 16, scale: 1),
    IconFile(pointSize: 16, scale: 2),
    IconFile(pointSize: 32, scale: 1),
    IconFile(pointSize: 32, scale: 2),
    IconFile(pointSize: 128, scale: 1),
    IconFile(pointSize: 128, scale: 2),
    IconFile(pointSize: 256, scale: 1),
    IconFile(pointSize: 256, scale: 2),
    IconFile(pointSize: 512, scale: 1),
    IconFile(pointSize: 512, scale: 2)
]

for iconFile in iconFiles {
    let image = drawIcon(size: CGFloat(iconFile.pixelSize))
    let destination = iconsetDirectory.appendingPathComponent(iconFile.fileName)
    try writePNG(image, to: destination)
}

try validateIconFiles(iconFiles, in: iconsetDirectory)

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
print("Generated supported macOS icon sizes:")
iconFiles.forEach { print("  \($0.fileName) (\($0.pixelSize)x\($0.pixelSize) px)") }

struct IconFile {
    let pointSize: Int
    let scale: Int

    var pixelSize: Int {
        pointSize * scale
    }

    var fileName: String {
        if scale == 1 {
            return "icon_\(pointSize)x\(pointSize).png"
        }

        return "icon_\(pointSize)x\(pointSize)@\(scale)x.png"
    }
}

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

func validateIconFiles(_ iconFiles: [IconFile], in iconsetDirectory: URL) throws {
    let missingFiles = iconFiles
        .map(\.fileName)
        .filter { !FileManager.default.fileExists(atPath: iconsetDirectory.appendingPathComponent($0).path) }

    guard missingFiles.isEmpty else {
        throw IconGenerationError.missingIconFiles(missingFiles)
    }
}

enum IconGenerationError: Error, CustomStringConvertible {
    case pngEncodingFailed(String)
    case iconutilFailed(Int32)
    case missingIconFiles([String])

    var description: String {
        switch self {
        case let .pngEncodingFailed(path):
            return "Could not encode PNG at \(path)"
        case let .iconutilFailed(status):
            return "iconutil failed with status \(status)"
        case let .missingIconFiles(files):
            return "Missing generated icon files: \(files.joined(separator: ", "))"
        }
    }
}
