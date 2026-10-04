import AppKit

enum CodexMenuBarIcon {
    // MenuBarExtra uses the native image size, not SwiftUI frame modifiers.
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }

            let transform = NSAffineTransform()
            transform.translateX(by: rect.minX, yBy: rect.minY)
            transform.scaleX(by: rect.width / 18, yBy: rect.height / 18)
            transform.concat()

            // Keep the Codex cloud and terminal glyph, without an app-icon tile.
            // Only black strokes and transparency belong in a template image.
            NSColor.black.setStroke()

            let outline = NSBezierPath()
            outline.move(to: NSPoint(x: 9, y: 16.7))
            outline.curve(to: NSPoint(x: 12, y: 15.5),
                          controlPoint1: NSPoint(x: 10.4, y: 16.7),
                          controlPoint2: NSPoint(x: 11.4, y: 16.4))
            outline.curve(to: NSPoint(x: 16.2, y: 11.8),
                          controlPoint1: NSPoint(x: 14.7, y: 16.1),
                          controlPoint2: NSPoint(x: 16.8, y: 14))
            outline.curve(to: NSPoint(x: 16, y: 9.4),
                          controlPoint1: NSPoint(x: 16.7, y: 11),
                          controlPoint2: NSPoint(x: 16.6, y: 10.3))
            outline.curve(to: NSPoint(x: 16.6, y: 5.8),
                          controlPoint1: NSPoint(x: 17.5, y: 8),
                          controlPoint2: NSPoint(x: 17.4, y: 6.7))
            outline.curve(to: NSPoint(x: 12.5, y: 3.1),
                          controlPoint1: NSPoint(x: 15.9, y: 4.2),
                          controlPoint2: NSPoint(x: 14.3, y: 3.2))
            outline.curve(to: NSPoint(x: 8.8, y: 1.2),
                          controlPoint1: NSPoint(x: 11.8, y: 1.6),
                          controlPoint2: NSPoint(x: 10.2, y: 0.8))
            outline.curve(to: NSPoint(x: 6, y: 2.2),
                          controlPoint1: NSPoint(x: 7.7, y: 1.2),
                          controlPoint2: NSPoint(x: 6.7, y: 1.5))
            outline.curve(to: NSPoint(x: 2.4, y: 3.8),
                          controlPoint1: NSPoint(x: 3.7, y: 1.6),
                          controlPoint2: NSPoint(x: 2.2, y: 2.4))
            outline.curve(to: NSPoint(x: 2.1, y: 8),
                          controlPoint1: NSPoint(x: 1.4, y: 4.7),
                          controlPoint2: NSPoint(x: 1.4, y: 6.5))
            outline.curve(to: NSPoint(x: 1.7, y: 11.7),
                          controlPoint1: NSPoint(x: 0.6, y: 9.2),
                          controlPoint2: NSPoint(x: 0.8, y: 10.7))
            outline.curve(to: NSPoint(x: 5, y: 14.2),
                          controlPoint1: NSPoint(x: 2.5, y: 13.2),
                          controlPoint2: NSPoint(x: 3.7, y: 14))
            outline.curve(to: NSPoint(x: 9, y: 16.7),
                          controlPoint1: NSPoint(x: 5.7, y: 15.9),
                          controlPoint2: NSPoint(x: 7.3, y: 16.7))
            outline.close()
            outline.lineWidth = 1.25
            outline.lineJoinStyle = .round
            outline.stroke()

            let terminal = NSBezierPath()
            terminal.move(to: NSPoint(x: 6.1, y: 11.9))
            terminal.line(to: NSPoint(x: 8.25, y: 8.95))
            terminal.line(to: NSPoint(x: 6.1, y: 6))
            terminal.move(to: NSPoint(x: 10.2, y: 6.2))
            terminal.line(to: NSPoint(x: 13.15, y: 6.2))
            terminal.lineWidth = 1.4
            terminal.lineCapStyle = .round
            terminal.lineJoinStyle = .round
            terminal.stroke()

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "CodexPoolManager"
        return image
    }()
}
