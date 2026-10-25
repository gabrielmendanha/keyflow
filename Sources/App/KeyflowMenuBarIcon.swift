import AppKit

enum KeyflowMenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.white.setStroke()
            NSColor.white.setFill()

            let body = NSBezierPath(roundedRect: NSRect(x: 1.25, y: 2.0, width: 15.5, height: 14.0),
                                    xRadius: 3.0, yRadius: 3.0)
            body.lineWidth = 1.2
            body.stroke()

            let keySize = NSSize(width: 2.65, height: 2.65)
            for row in 0..<3 {
                for column in 0..<2 {
                    let frame = NSRect(x: 3.1 + CGFloat(column) * 3.65,
                                       y: 4.05 + CGFloat(row) * 3.55,
                                       width: keySize.width,
                                       height: keySize.height)
                    NSBezierPath(roundedRect: frame, xRadius: 0.65, yRadius: 0.65).fill()
                }
            }

            let knob = NSRect(x: 10.9, y: 6.8, width: 4.0, height: 4.0)
            let knobPath = NSBezierPath(ovalIn: knob)
            knobPath.lineWidth = 1.15
            knobPath.stroke()

            let indicator = NSBezierPath()
            indicator.lineWidth = 1.0
            indicator.lineCapStyle = .round
            indicator.move(to: NSPoint(x: 12.9, y: 8.8))
            indicator.line(to: NSPoint(x: 12.9, y: 10.0))
            indicator.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
