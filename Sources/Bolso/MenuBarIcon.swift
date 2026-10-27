import AppKit

/// A small vector counterpart of the app icon: two cards in a pocket.
/// Template rendering lets macOS choose the correct color for the menu bar.
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let cards = NSBezierPath()
            cards.lineWidth = 1.35
            cards.lineJoinStyle = .round
            cards.lineCapStyle = .round
            cards.move(to: NSPoint(x: 4.5, y: 10))
            cards.line(to: NSPoint(x: 4.5, y: 16))
            cards.line(to: NSPoint(x: 11, y: 16))
            cards.line(to: NSPoint(x: 11, y: 13.5))
            cards.move(to: NSPoint(x: 7.5, y: 10))
            cards.line(to: NSPoint(x: 7.5, y: 13.5))
            cards.line(to: NSPoint(x: 13.5, y: 13.5))
            cards.line(to: NSPoint(x: 13.5, y: 10))
            cards.stroke()

            let pocket = NSBezierPath()
            pocket.lineWidth = 1.5
            pocket.lineJoinStyle = .round
            pocket.move(to: NSPoint(x: 2.5, y: 10))
            pocket.line(to: NSPoint(x: 15.5, y: 10))
            pocket.line(to: NSPoint(x: 15, y: 5))
            pocket.curve(to: NSPoint(x: 9, y: 1.5), controlPoint1: NSPoint(x: 14.7, y: 2.5), controlPoint2: NSPoint(x: 11.5, y: 1.5))
            pocket.curve(to: NSPoint(x: 3, y: 5), controlPoint1: NSPoint(x: 6.5, y: 1.5), controlPoint2: NSPoint(x: 3.3, y: 2.5))
            pocket.close()
            pocket.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Bolso"
        return image
    }
}
