// The Finder window and icon positions are set in dmg-settings.py, in points.
import AppKit

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift Tools/render-dmg.swift OUTPUT.tiff")
}

let size = NSSize(width: 640, height: 400)
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 1280, pixelsHigh: 800,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
bitmap.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
// Finder keeps icon names black on picture backgrounds, including in Dark Mode.
NSColor(white: 0.86, alpha: 1).setFill()
NSRect(x: 0, y: 92, width: size.width, height: 178).fill()

func text(_ value: String, y: CGFloat, font: NSFont, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    (value as NSString).draw(in: NSRect(x: 32, y: y, width: 576, height: 42), withAttributes: [
        .font: font, .foregroundColor: color, .paragraphStyle: paragraph
    ])
}

text("loge", y: 326, font: .systemFont(ofSize: 32, weight: .semibold), color: .white)
text("Drag loge to Applications", y: 290, font: .systemFont(ofSize: 16),
     color: NSColor(white: 0.8, alpha: 1))

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 296, y: 190))
arrow.line(to: NSPoint(x: 344, y: 190))
arrow.move(to: NSPoint(x: 334, y: 200))
arrow.line(to: NSPoint(x: 344, y: 190))
arrow.line(to: NSPoint(x: 334, y: 180))
arrow.lineWidth = 1.5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
NSColor(white: 0.4, alpha: 1).setStroke()
arrow.stroke()

text("First launch: open loge from Applications.", y: 29,
     font: .systemFont(ofSize: 12), color: NSColor(white: 0.72, alpha: 1))
text("If macOS blocks it: System Settings → Privacy & Security → Open Anyway.", y: 9,
     font: .systemFont(ofSize: 11), color: NSColor(white: 0.55, alpha: 1))

NSGraphicsContext.restoreGraphicsState()
try bitmap.tiffRepresentation!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
