#!/usr/bin/env swift
import AppKit
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let out = URL(
    fileURLWithPath: arguments.first ?? "build/Surma-Light.iconset",
    isDirectory: true
)
let variant = arguments.dropFirst().first ?? "light"
guard variant == "light" || variant == "dark" else {
    fputs("Usage: make-icon.swift <output.iconset> [light|dark]\n", stderr)
    exit(2)
}

try? FileManager.default.removeItem(at: out)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func mountainPath(_ size: CGFloat) -> NSBezierPath {
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: x * size, y: y * size)
    }

    let path = NSBezierPath()
    path.move(to: point(0.19, 0.39))
    path.curve(
        to: point(0.49, 0.60),
        controlPoint1: point(0.33, 0.42),
        controlPoint2: point(0.42, 0.58)
    )
    path.curve(
        to: point(0.58, 0.52),
        controlPoint1: point(0.53, 0.61),
        controlPoint2: point(0.55, 0.56)
    )
    path.curve(
        to: point(0.81, 0.39),
        controlPoint1: point(0.65, 0.45),
        controlPoint2: point(0.73, 0.41)
    )
    path.lineWidth = max(1, size * 0.032)
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    return path
}

func draw(_ pixels: Int, to url: URL) throws {
    let size = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "SurmaIcon", code: 1)
    }

    rep.size = NSSize(width: size, height: size)
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "SurmaIcon", code: 2)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.shouldAntialias = true

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let inset = size * 0.055
    let tile = NSBezierPath(
        roundedRect: NSRect(
            x: inset,
            y: inset,
            width: size - 2 * inset,
            height: size - 2 * inset
        ),
        xRadius: size * 0.19,
        yRadius: size * 0.19
    )

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(variant == "dark" ? 0.30 : 0.14)
    shadow.shadowBlurRadius = size * 0.028
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    shadow.set()

    let background = variant == "dark"
        ? NSColor(calibratedWhite: 0.105, alpha: 1)
        : NSColor(calibratedWhite: 0.992, alpha: 1)
    background.setFill()
    tile.fill()

    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.shouldAntialias = true

    let mark = variant == "dark"
        ? NSColor(calibratedWhite: 0.97, alpha: 1)
        : NSColor(calibratedWhite: 0.045, alpha: 1)
    mark.setStroke()
    mountainPath(size).stroke()

    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [.compressionFactor: 1]) else {
        throw NSError(domain: "SurmaIcon", code: 3)
    }
    try data.write(to: url)
}

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, size) in specs {
    try draw(size, to: out.appendingPathComponent(name))
}
