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

    let iconSize = CGFloat(size)
    let inset = iconSize * 0.055
    let background = NSBezierPath(
        roundedRect: rect.insetBy(dx: inset, dy: inset),
        xRadius: iconSize * 0.22,
        yRadius: iconSize * 0.22
    )
    NSGradient(colors: [
        NSColor(red: 0.13, green: 0.11, blue: 0.09, alpha: 1),
        NSColor(red: 0.06, green: 0.055, blue: 0.05, alpha: 1),
    ])?.draw(in: background, angle: -90)

    let cream = NSColor(red: 1.0, green: 0.973, blue: 0.91, alpha: 1)
    let amber = NSColor(red: 0.96, green: 0.58, blue: 0.19, alpha: 1)
    let cupFill = NSColor(red: 0.075, green: 0.067, blue: 0.058, alpha: 1)
    let cupStrokeWidth = max(1.5, iconSize * 0.062)

    let handle = NSBezierPath()
    handle.lineWidth = cupStrokeWidth
    handle.lineCapStyle = .round
    handle.move(to: CGPoint(x: iconSize * 0.64, y: iconSize * 0.53))
    handle.curve(
        to: CGPoint(x: iconSize * 0.64, y: iconSize * 0.40),
        controlPoint1: CGPoint(x: iconSize * 0.87, y: iconSize * 0.55),
        controlPoint2: CGPoint(x: iconSize * 0.87, y: iconSize * 0.38)
    )
    cream.setStroke()
    handle.stroke()

    let cup = NSBezierPath()
    cup.lineWidth = cupStrokeWidth
    cup.lineCapStyle = .round
    cup.lineJoinStyle = .round
    cup.move(to: CGPoint(x: iconSize * 0.25, y: iconSize * 0.58))
    cup.line(to: CGPoint(x: iconSize * 0.68, y: iconSize * 0.58))
    cup.line(to: CGPoint(x: iconSize * 0.68, y: iconSize * 0.42))
    cup.curve(
        to: CGPoint(x: iconSize * 0.465, y: iconSize * 0.25),
        controlPoint1: CGPoint(x: iconSize * 0.68, y: iconSize * 0.31),
        controlPoint2: CGPoint(x: iconSize * 0.58, y: iconSize * 0.25)
    )
    cup.curve(
        to: CGPoint(x: iconSize * 0.25, y: iconSize * 0.42),
        controlPoint1: CGPoint(x: iconSize * 0.35, y: iconSize * 0.25),
        controlPoint2: CGPoint(x: iconSize * 0.25, y: iconSize * 0.31)
    )
    cup.close()
    cupFill.setFill()
    cup.fill()
    cream.setStroke()
    cup.stroke()

    let saucer = NSBezierPath()
    saucer.lineWidth = max(1.5, iconSize * 0.052)
    saucer.lineCapStyle = .round
    saucer.move(to: CGPoint(x: iconSize * 0.22, y: iconSize * 0.18))
    saucer.line(to: CGPoint(x: iconSize * 0.73, y: iconSize * 0.18))
    saucer.stroke()

    amber.setStroke()
    for steamX in [0.37, 0.52] {
        let steam = NSBezierPath()
        steam.lineWidth = max(1.3, iconSize * 0.045)
        steam.lineCapStyle = .round
        steam.move(to: CGPoint(x: iconSize * steamX, y: iconSize * 0.66))
        steam.curve(
            to: CGPoint(x: iconSize * steamX, y: iconSize * 0.86),
            controlPoint1: CGPoint(x: iconSize * (steamX - 0.085), y: iconSize * 0.73),
            controlPoint2: CGPoint(x: iconSize * (steamX + 0.085), y: iconSize * 0.79)
        )
        steam.stroke()
    }

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
