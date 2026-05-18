import AppKit

enum StatusIconFactory {
    static func image(isMuted: Bool, error: Bool = false) -> NSImage {
        let size = NSSize(width: 24, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let stroke = NSBezierPath()
        stroke.lineWidth = 1.9
        stroke.lineCapStyle = .round
        stroke.lineJoinStyle = .round

        let micBody = NSBezierPath(roundedRect: NSRect(x: 7.2, y: 6.6, width: 6.8, height: 8.6), xRadius: 3.4, yRadius: 3.4)
        micBody.lineWidth = 1.8
        NSColor.labelColor.setStroke()
        micBody.stroke()

        stroke.move(to: NSPoint(x: 5.2, y: 9.9))
        stroke.curve(to: NSPoint(x: 10.6, y: 4.4), controlPoint1: NSPoint(x: 5.2, y: 6.7), controlPoint2: NSPoint(x: 7.2, y: 4.4))
        stroke.curve(to: NSPoint(x: 16.0, y: 9.9), controlPoint1: NSPoint(x: 14.0, y: 4.4), controlPoint2: NSPoint(x: 16.0, y: 6.7))
        stroke.move(to: NSPoint(x: 10.6, y: 4.4))
        stroke.line(to: NSPoint(x: 10.6, y: 1.8))
        stroke.move(to: NSPoint(x: 7.6, y: 1.8))
        stroke.line(to: NSPoint(x: 13.6, y: 1.8))
        stroke.stroke()

        if isMuted {
            let slash = NSBezierPath()
            slash.lineWidth = 2.0
            slash.lineCapStyle = .round
            NSColor.labelColor.setStroke()
            slash.move(to: NSPoint(x: 4.6, y: 2.8))
            slash.line(to: NSPoint(x: 16.6, y: 15.2))
            slash.stroke()
        }

        let indicatorColor: NSColor
        if error {
            indicatorColor = .systemYellow
        } else {
            indicatorColor = isMuted ? .systemRed : .systemGreen
        }

        indicatorColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 18.0, y: 2.4, width: 5.4, height: 5.4)).fill()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
