import AppKit

/// Rounded Union Jack and heart, rendered as a native menu-bar template.
enum MenuIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 19, height: 18), flipped: false) { _ in
            let flag = NSBezierPath(roundedRect: NSRect(x: 0.75, y: 4.5, width: 16.5, height: 12.5), xRadius: 2.5, yRadius: 2.5)
            NSColor.black.setFill(); flag.fill()
            NSGraphicsContext.saveGraphicsState(); flag.addClip()
            let diagonals = NSBezierPath()
            diagonals.move(to: NSPoint(x: 0.75, y: 4.5)); diagonals.line(to: NSPoint(x: 17.25, y: 17))
            diagonals.move(to: NSPoint(x: 0.75, y: 17)); diagonals.line(to: NSPoint(x: 17.25, y: 4.5))
            let cross = NSBezierPath()
            cross.move(to: NSPoint(x: 9, y: 4.5)); cross.line(to: NSPoint(x: 9, y: 17))
            cross.move(to: NSPoint(x: 0.75, y: 10.75)); cross.line(to: NSPoint(x: 17.25, y: 10.75))
            NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
            diagonals.lineWidth = 1.8; diagonals.stroke()
            cross.lineWidth = 3.2; cross.stroke()
            NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
            NSColor.black.setStroke()
            cross.lineWidth = 1.25; cross.stroke()
            NSGraphicsContext.restoreGraphicsState()
            let heart = NSBezierPath()
            heart.move(to: NSPoint(x: 14.6, y: 1.2))
            heart.curve(to: NSPoint(x: 11.2, y: 5.1), controlPoint1: NSPoint(x: 13.3, y: 2.3), controlPoint2: NSPoint(x: 11.2, y: 3.5))
            heart.curve(to: NSPoint(x: 14.6, y: 5.9), controlPoint1: NSPoint(x: 11.2, y: 7.5), controlPoint2: NSPoint(x: 13.3, y: 7.7))
            heart.curve(to: NSPoint(x: 18, y: 5.1), controlPoint1: NSPoint(x: 15.9, y: 7.7), controlPoint2: NSPoint(x: 18, y: 7.5))
            heart.curve(to: NSPoint(x: 14.6, y: 1.2), controlPoint1: NSPoint(x: 18, y: 3.5), controlPoint2: NSPoint(x: 15.9, y: 2.3))
            heart.close()
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
            heart.lineWidth = 1.4; heart.lineJoinStyle = .round; heart.stroke(); heart.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.black.setFill(); heart.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "WordShelf 单词清单"
        return image
    }()
}
