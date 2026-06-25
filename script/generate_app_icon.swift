import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "dist/DontDieOnMeNow.icns"
let outputURL = URL(fileURLWithPath: outputPath)
let iconsetURL = outputURL.deletingPathExtension().appendingPathExtension("iconset")

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let variants: [(points: Int, scale: Int, name: String)] = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png"),
]

func pngData(size: Int) throws -> Data {
    guard let rep = NSBitmapImageRep(
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
    ) else {
        throw NSError(domain: "Icon", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    let inset = CGFloat(size) * 0.055
    let background = NSBezierPath(
        roundedRect: rect.insetBy(dx: inset, dy: inset),
        xRadius: CGFloat(size) * 0.22,
        yRadius: CGFloat(size) * 0.22
    )
    NSGradient(colors: [
        NSColor(red: 0.08, green: 0.10, blue: 0.15, alpha: 1),
        NSColor(red: 0.13, green: 0.36, blue: 0.30, alpha: 1),
        NSColor(red: 0.95, green: 0.60, blue: 0.20, alpha: 1),
    ])?.draw(in: background, angle: -35)

    let moonRect = CGRect(
        x: CGFloat(size) * 0.20,
        y: CGFloat(size) * 0.26,
        width: CGFloat(size) * 0.36,
        height: CGFloat(size) * 0.48
    )
    NSColor(red: 0.98, green: 0.96, blue: 0.82, alpha: 1).setFill()
    NSBezierPath(ovalIn: moonRect).fill()
    NSColor(red: 0.13, green: 0.36, blue: 0.30, alpha: 1).setFill()
    NSBezierPath(ovalIn: moonRect.offsetBy(dx: CGFloat(size) * 0.13, dy: CGFloat(size) * 0.06)).fill()

    let center = CGPoint(x: CGFloat(size) * 0.67, y: CGFloat(size) * 0.50)
    let ring = NSBezierPath()
    ring.lineWidth = max(2, CGFloat(size) * 0.058)
    ring.lineCapStyle = .round
    ring.appendArc(
        withCenter: center,
        radius: CGFloat(size) * 0.15,
        startAngle: 42,
        endAngle: 318,
        clockwise: false
    )
    NSColor.white.withAlphaComponent(0.93).setStroke()
    ring.stroke()

    let stem = NSBezierPath()
    stem.lineWidth = max(2, CGFloat(size) * 0.058)
    stem.lineCapStyle = .round
    stem.move(to: CGPoint(x: center.x, y: CGFloat(size) * 0.72))
    stem.line(to: CGPoint(x: center.x, y: CGFloat(size) * 0.53))
    stem.stroke()

    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "Icon", code: 2)
    }
    return data
}

for variant in variants {
    let size = variant.points * variant.scale
    try pngData(size: size).write(to: iconsetURL.appendingPathComponent(variant.name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "Icon", code: Int(process.terminationStatus))
}

