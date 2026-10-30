// Renders every app icon and Apple TV top-shelf image into App/Assets.xcassets.
// Run from the repository root: swift Tools/render-icons.swift
//
// The mark is Loge's "l", a white stroke with a turned foot on the app's charcoal canvas.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas = CGColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1)
let catalog = URL(fileURLWithPath: "App/Assets.xcassets")

enum Layer { case full, back, front }

/// Draws the mark centred in a `width`×`height` image, sized relative to the shorter side.
func render(width: Int, height: Int, layer: Layer, markScale: CGFloat = 0.62) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let w = CGFloat(width), h = CGFloat(height)
    if layer != .front {
        context.setFillColor(canvas)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
    }
    if layer != .back {
        let size = min(w, h) * markScale
        let origin = CGPoint(x: (w - size) / 2, y: (h - size) / 2)

        // A lowercase "l" whose foot turns out to the right; centred on the whole glyph, foot included.
        let stroke = size * 0.13, height = size * 0.66, foot = size * 0.16
        let x = origin.x + size / 2 - foot / 2
        let top = origin.y + (size + height) / 2, bottom = origin.y + (size - height) / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x, y: top))
        path.addLine(to: CGPoint(x: x, y: bottom + foot))
        path.addArc(center: CGPoint(x: x + foot, y: bottom + foot), radius: foot, startAngle: .pi, endAngle: .pi * 1.5, clockwise: false)
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(stroke)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path)
        context.strokePath()
    }
    return context.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
}

func writeJSON(_ object: Any, to url: URL) {
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: url.appending(path: "Contents.json"))
}

let info = ["author": "xcode", "version": 1] as [String: Any]
try? FileManager.default.removeItem(at: catalog)
writeJSON(["info": info], to: catalog)

// iOS takes one 1024-point image; macOS still wants each size. Both systems apply their own masks.
let appIcon = catalog.appending(path: "AppIcon.appiconset")
write(render(width: 1024, height: 1024, layer: .full), to: appIcon.appending(path: "icon-1024.png"))
var iconImages: [[String: String]] = [
    ["filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"],
]
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let file = "mac-\(pixels).png"
        if !FileManager.default.fileExists(atPath: appIcon.appending(path: file).path) {
            write(render(width: pixels, height: pixels, layer: .full), to: appIcon.appending(path: file))
        }
        iconImages.append(["filename": file, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
writeJSON(["images": iconImages, "info": info], to: appIcon)

// tvOS: layered icons for the parallax effect, plus top-shelf images.
let brand = catalog.appending(path: "App Icon & Top Shelf Image.brandassets")
func imageStack(_ name: String, width: Int, height: Int, scales: [Int]) {
    let stack = brand.appending(path: "\(name).imagestack")
    for (layerName, layer) in [("Front", Layer.front), ("Back", Layer.back)] {
        let set = stack.appending(path: "\(layerName).imagestacklayer/Content.imageset")
        var images: [[String: String]] = []
        for scale in scales {
            let file = "\(layerName.lowercased())@\(scale)x.png"
            write(render(width: width * scale, height: height * scale, layer: layer), to: set.appending(path: file))
            images.append(["filename": file, "idiom": "tv", "scale": "\(scale)x"])
        }
        writeJSON(["images": images, "info": info], to: set)
        writeJSON(["info": info], to: stack.appending(path: "\(layerName).imagestacklayer"))
    }
    writeJSON(["info": info, "layers": [["filename": "Front.imagestacklayer"], ["filename": "Back.imagestacklayer"]]], to: stack)
}
func topShelf(_ name: String, width: Int, height: Int) {
    let set = brand.appending(path: "\(name).imageset")
    var images: [[String: String]] = []
    for scale in [1, 2] {
        let file = "shelf@\(scale)x.png"
        write(render(width: width * scale, height: height * scale, layer: .full, markScale: 0.4), to: set.appending(path: file))
        images.append(["filename": file, "idiom": "tv", "scale": "\(scale)x"])
    }
    writeJSON(["images": images, "info": info], to: set)
}
imageStack("App Icon", width: 400, height: 240, scales: [1, 2])
imageStack("App Icon - App Store", width: 1280, height: 768, scales: [1])
topShelf("Top Shelf Image", width: 1920, height: 720)
topShelf("Top Shelf Image Wide", width: 2320, height: 720)
writeJSON([
    "assets": [
        ["filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
        ["filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"],
        ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"],
        ["filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"],
    ],
    "info": info,
], to: brand)

// White accent: artwork carries the colour, so controls, selection and focus stay neutral.
// The asset form also reaches system chrome such as the Mac sidebar, which .tint doesn't.
// On the Mac it also fills the selected sidebar row behind white text, so it's grey there.
func accent(_ gray: String, idiom: String) -> [String: Any] {
    ["color": ["color-space": "srgb", "components": ["red": gray, "green": gray, "blue": gray, "alpha": "1.000"]], "idiom": idiom]
}
writeJSON([
    "colors": [accent("1.000", idiom: "universal"), accent("0.380", idiom: "mac")],
    "info": info,
], to: catalog.appending(path: "AccentColor.colorset"))

print("Wrote \(catalog.path)")
