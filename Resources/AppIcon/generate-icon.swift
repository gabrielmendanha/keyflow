import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: generate-icon.swift OUTPUT_ICONSET_DIRECTORY")
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func color(_ rgb: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((rgb >> 16) & 0xff) / 255,
        green: CGFloat((rgb >> 8) & 0xff) / 255,
        blue: CGFloat(rgb & 0xff) / 255,
        alpha: alpha
    )
}

func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func renderIcon(pixelSize: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "KeyflowIcon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Could not allocate icon bitmap"])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let scale = CGFloat(pixelSize)
    let canvas = NSRect(x: 0, y: 0, width: scale, height: scale)

    let background = NSBezierPath(rect: canvas)
    NSGradient(colors: [color(0x7468F2), color(0x3F55D9), color(0x16234B)])?
        .draw(in: background, angle: -42)

    let plate = NSRect(x: scale * 0.115, y: scale * 0.165,
                       width: scale * 0.77, height: scale * 0.67)
    let platePath = roundedRect(plate, radius: scale * 0.115)
    let shadow = NSShadow()
    shadow.shadowColor = color(0x080C21, alpha: 0.45)
    shadow.shadowBlurRadius = scale * 0.035
    shadow.shadowOffset = NSSize(width: 0, height: -scale * 0.018)
    shadow.set()
    NSGradient(colors: [color(0x293762), color(0x151E3A)])?.draw(in: platePath, angle: 90)
    NSShadow().set()
    color(0xD8E1FF, alpha: 0.8).setStroke()
    platePath.lineWidth = scale * 0.018
    platePath.stroke()

    let keyWidth = scale * 0.19
    let keyHeight = scale * 0.155
    let keyRadius = scale * 0.035
    let firstKeyX = plate.minX + scale * 0.075
    let firstKeyY = plate.minY + scale * 0.085
    for row in 0..<3 {
        for column in 0..<2 {
            let frame = NSRect(
                x: firstKeyX + CGFloat(column) * scale * 0.215,
                y: firstKeyY + CGFloat(row) * scale * 0.185,
                width: keyWidth,
                height: keyHeight
            )
            let key = roundedRect(frame, radius: keyRadius)
            NSGradient(colors: [color(0xE8EEFF), color(0x9DAEFF)])?.draw(in: key, angle: 90)
            color(0xFFFFFF, alpha: 0.7).setStroke()
            key.lineWidth = scale * 0.008
            key.stroke()
        }
    }

    let knobCenter = NSPoint(x: plate.maxX - scale * 0.155, y: plate.midY)
    let outerKnob = NSRect(x: knobCenter.x - scale * 0.11, y: knobCenter.y - scale * 0.11,
                           width: scale * 0.22, height: scale * 0.22)
    let outerPath = NSBezierPath(ovalIn: outerKnob)
    NSGradient(colors: [color(0x83F0EA), color(0x28B8C4)])?.draw(in: outerPath, angle: 90)
    color(0xB9FFFA).setStroke()
    outerPath.lineWidth = scale * 0.012
    outerPath.stroke()

    let innerKnob = outerKnob.insetBy(dx: scale * 0.032, dy: scale * 0.032)
    color(0x182747).setFill()
    NSBezierPath(ovalIn: innerKnob).fill()
    color(0xE7FFFC).setStroke()
    let indicator = NSBezierPath()
    indicator.lineWidth = scale * 0.018
    indicator.lineCapStyle = .round
    indicator.move(to: knobCenter)
    indicator.line(to: NSPoint(x: knobCenter.x, y: knobCenter.y + scale * 0.065))
    indicator.stroke()

    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "KeyflowIcon", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Could not encode icon PNG"])
    }
    return data
}

let iconFiles: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (filename, size) in iconFiles {
    try renderIcon(pixelSize: size).write(to: outputDirectory.appendingPathComponent(filename))
}
