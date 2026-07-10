import AppKit
import SwiftUI

struct MenuBarStatusIcon: View {
    let icon: MenuBarIcon
    let size: CGFloat

    var body: some View {
        Group {
            switch icon {
            case let .coffee(steaming):
                Image(nsImage: CoffeeCupMenuBarImage.image(steaming: steaming))
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            case let .system(name):
                Image(systemName: name)
                    .font(.system(size: size * 0.88, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

enum CoffeeCupMenuBarImage {
    static let artworkVerticalOffset: CGFloat = 2
    private static let ready = makeImage(steaming: false)
    private static let awake = makeImage(steaming: true)

    static func image(steaming: Bool) -> NSImage {
        steaming ? awake : ready
    }

    private static func makeImage(steaming: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
            NSGraphicsContext.current?.cgContext.saveGState()
            NSGraphicsContext.current?.cgContext.translateBy(x: 0, y: artworkVerticalOffset)
            defer {
                NSGraphicsContext.current?.cgContext.restoreGState()
            }

            NSColor.black.setStroke()

            let handle = NSBezierPath()
            handle.lineWidth = 1.8
            handle.lineCapStyle = .round
            handle.move(to: CGPoint(x: 13.7, y: 10.8))
            handle.curve(
                to: CGPoint(x: 13.7, y: 6.3),
                controlPoint1: CGPoint(x: 18.4, y: 10.8),
                controlPoint2: CGPoint(x: 18.4, y: 6.3)
            )
            handle.stroke()

            let cup = NSBezierPath()
            cup.lineWidth = 1.9
            cup.lineCapStyle = .round
            cup.lineJoinStyle = .round
            cup.move(to: CGPoint(x: 2.8, y: 12.4))
            cup.line(to: CGPoint(x: 13.9, y: 12.4))
            cup.line(to: CGPoint(x: 13.9, y: 8.2))
            cup.curve(
                to: CGPoint(x: 8.4, y: 2.9),
                controlPoint1: CGPoint(x: 13.9, y: 4.9),
                controlPoint2: CGPoint(x: 11.5, y: 2.9)
            )
            cup.curve(
                to: CGPoint(x: 2.8, y: 8.2),
                controlPoint1: CGPoint(x: 5.3, y: 2.9),
                controlPoint2: CGPoint(x: 2.8, y: 4.9)
            )
            cup.close()
            cup.stroke()

            let saucer = NSBezierPath()
            saucer.lineWidth = 1.8
            saucer.lineCapStyle = .round
            saucer.move(to: CGPoint(x: 1.9, y: 1.1))
            saucer.line(to: CGPoint(x: 15.4, y: 1.1))
            saucer.stroke()

            if steaming {
                drawSteam(atX: 5.7)
                drawSteam(atX: 10.2)
            }

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = steaming ? "Keeping awake" : "Ready"
        return image
    }

    private static func drawSteam(atX x: CGFloat) {
        let steam = NSBezierPath()
        steam.lineWidth = 1.45
        steam.lineCapStyle = .round
        steam.move(to: CGPoint(x: x, y: 14.2))
        steam.curve(
            to: CGPoint(x: x, y: 18.7),
            controlPoint1: CGPoint(x: x - 2.0, y: 15.7),
            controlPoint2: CGPoint(x: x + 2.0, y: 17.1)
        )
        steam.stroke()
    }
}
