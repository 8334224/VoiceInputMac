#!/usr/bin/env swift

import AppKit
import Foundation

struct IconSpec {
    let filename: String
    let size: Int
}

let specs: [IconSpec] = [
    .init(filename: "icon_16x16.png", size: 16),
    .init(filename: "icon_16x16@2x.png", size: 32),
    .init(filename: "icon_32x32.png", size: 32),
    .init(filename: "icon_32x32@2x.png", size: 64),
    .init(filename: "icon_128x128.png", size: 128),
    .init(filename: "icon_128x128@2x.png", size: 256),
    .init(filename: "icon_256x256.png", size: 256),
    .init(filename: "icon_256x256@2x.png", size: 512),
    .init(filename: "icon_512x512.png", size: 512),
    .init(filename: "icon_512x512@2x.png", size: 1024),
]

let arguments = CommandLine.arguments
let root = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : ".").standardizedFileURL
let fileManager = FileManager.default
let resourcesURL = root.appendingPathComponent("Resources", isDirectory: true)
let iconsetURL = resourcesURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let icnsURL = resourcesURL.appendingPathComponent("VoiceInputMac.icns")

try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for spec in specs {
    let image = renderIcon(size: CGFloat(spec.size))
    let data = try pngData(from: image)
    try data.write(to: iconsetURL.appendingPathComponent(spec.filename))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    fputs("iconutil failed with status \(process.terminationStatus)\n", stderr)
    exit(process.terminationStatus)
}

func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    drawBackground(in: rect)
    drawCatHead(in: rect)
    drawFace(in: rect)
    drawWhiskers(in: rect)

    image.unlockFocus()
    return image
}

func drawBackground(in rect: NSRect) {
    let bgRect = rect.insetBy(dx: rect.width * 0.05, dy: rect.height * 0.05)
    let bg = NSBezierPath(roundedRect: bgRect, xRadius: rect.width * 0.24, yRadius: rect.width * 0.24)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.98, green: 0.78, blue: 0.44, alpha: 1.0),
        NSColor(calibratedRed: 0.97, green: 0.58, blue: 0.34, alpha: 1.0),
        NSColor(calibratedRed: 0.90, green: 0.35, blue: 0.25, alpha: 1.0),
    ])!
    gradient.draw(in: bg, angle: -35)

    NSColor(calibratedWhite: 1.0, alpha: 0.08).setStroke()
    for idx in 0..<5 {
        let path = NSBezierPath()
        path.lineWidth = max(1, rect.width * 0.016)
        let offset = CGFloat(idx) * rect.width * 0.14 + rect.width * 0.1
        path.move(to: NSPoint(x: bgRect.minX + offset, y: bgRect.minY + rect.height * 0.06))
        path.curve(to: NSPoint(x: bgRect.minX + offset + rect.width * 0.06, y: bgRect.maxY - rect.height * 0.06),
                   controlPoint1: NSPoint(x: bgRect.minX + offset - rect.width * 0.03, y: rect.midY),
                   controlPoint2: NSPoint(x: bgRect.minX + offset + rect.width * 0.12, y: rect.midY))
        path.stroke()
    }
}

func drawCatHead(in rect: NSRect) {
    let fill = NSColor(calibratedRed: 0.19, green: 0.14, blue: 0.18, alpha: 0.96)
    fill.setFill()

    let faceRect = NSRect(
        x: rect.width * 0.20,
        y: rect.height * 0.18,
        width: rect.width * 0.60,
        height: rect.height * 0.58
    )

    let head = NSBezierPath(roundedRect: faceRect, xRadius: rect.width * 0.18, yRadius: rect.width * 0.18)
    head.fill()

    let leftEar = NSBezierPath()
    leftEar.move(to: NSPoint(x: rect.width * 0.26, y: rect.height * 0.62))
    leftEar.line(to: NSPoint(x: rect.width * 0.38, y: rect.height * 0.86))
    leftEar.line(to: NSPoint(x: rect.width * 0.48, y: rect.height * 0.63))
    leftEar.close()
    leftEar.fill()

    let rightEar = NSBezierPath()
    rightEar.move(to: NSPoint(x: rect.width * 0.74, y: rect.height * 0.62))
    rightEar.line(to: NSPoint(x: rect.width * 0.62, y: rect.height * 0.86))
    rightEar.line(to: NSPoint(x: rect.width * 0.52, y: rect.height * 0.63))
    rightEar.close()
    rightEar.fill()

    let innerEarColor = NSColor(calibratedRed: 0.98, green: 0.70, blue: 0.62, alpha: 0.95)
    innerEarColor.setFill()
    let leftInner = NSBezierPath()
    leftInner.move(to: NSPoint(x: rect.width * 0.31, y: rect.height * 0.65))
    leftInner.line(to: NSPoint(x: rect.width * 0.38, y: rect.height * 0.80))
    leftInner.line(to: NSPoint(x: rect.width * 0.43, y: rect.height * 0.66))
    leftInner.close()
    leftInner.fill()

    let rightInner = NSBezierPath()
    rightInner.move(to: NSPoint(x: rect.width * 0.69, y: rect.height * 0.65))
    rightInner.line(to: NSPoint(x: rect.width * 0.62, y: rect.height * 0.80))
    rightInner.line(to: NSPoint(x: rect.width * 0.57, y: rect.height * 0.66))
    rightInner.close()
    rightInner.fill()
}

func drawFace(in rect: NSRect) {
    let eyeColor = NSColor(calibratedRed: 0.34, green: 0.92, blue: 0.78, alpha: 1.0)
    eyeColor.setFill()

    let leftEye = NSBezierPath(ovalIn: NSRect(x: rect.width * 0.34, y: rect.height * 0.48, width: rect.width * 0.08, height: rect.height * 0.13))
    leftEye.fill()

    let rightEye = NSBezierPath(ovalIn: NSRect(x: rect.width * 0.58, y: rect.height * 0.48, width: rect.width * 0.08, height: rect.height * 0.13))
    rightEye.fill()

    NSColor(calibratedWhite: 1.0, alpha: 0.88).setFill()
    let muzzle = NSBezierPath(ovalIn: NSRect(x: rect.width * 0.37, y: rect.height * 0.24, width: rect.width * 0.26, height: rect.height * 0.22))
    muzzle.fill()

    let nose = NSBezierPath()
    nose.move(to: NSPoint(x: rect.width * 0.50, y: rect.height * 0.37))
    nose.line(to: NSPoint(x: rect.width * 0.46, y: rect.height * 0.33))
    nose.line(to: NSPoint(x: rect.width * 0.54, y: rect.height * 0.33))
    nose.close()
    NSColor(calibratedRed: 0.95, green: 0.46, blue: 0.50, alpha: 1.0).setFill()
    nose.fill()

    let mouth = NSBezierPath()
    mouth.lineWidth = max(2, rect.width * 0.014)
    NSColor(calibratedRed: 0.40, green: 0.23, blue: 0.22, alpha: 0.95).setStroke()
    mouth.move(to: NSPoint(x: rect.width * 0.50, y: rect.height * 0.33))
    mouth.line(to: NSPoint(x: rect.width * 0.50, y: rect.height * 0.28))
    mouth.move(to: NSPoint(x: rect.width * 0.50, y: rect.height * 0.28))
    mouth.curve(to: NSPoint(x: rect.width * 0.44, y: rect.height * 0.25),
                controlPoint1: NSPoint(x: rect.width * 0.49, y: rect.height * 0.25),
                controlPoint2: NSPoint(x: rect.width * 0.46, y: rect.height * 0.24))
    mouth.move(to: NSPoint(x: rect.width * 0.50, y: rect.height * 0.28))
    mouth.curve(to: NSPoint(x: rect.width * 0.56, y: rect.height * 0.25),
                controlPoint1: NSPoint(x: rect.width * 0.51, y: rect.height * 0.25),
                controlPoint2: NSPoint(x: rect.width * 0.54, y: rect.height * 0.24))
    mouth.stroke()
}

func drawWhiskers(in rect: NSRect) {
    let path = NSBezierPath()
    path.lineWidth = max(1, rect.width * 0.01)
    NSColor(calibratedWhite: 1.0, alpha: 0.82).setStroke()

    let whiskers: [(NSPoint, NSPoint)] = [
        (.init(x: rect.width * 0.18, y: rect.height * 0.39), .init(x: rect.width * 0.40, y: rect.height * 0.36)),
        (.init(x: rect.width * 0.17, y: rect.height * 0.33), .init(x: rect.width * 0.40, y: rect.height * 0.33)),
        (.init(x: rect.width * 0.19, y: rect.height * 0.27), .init(x: rect.width * 0.40, y: rect.height * 0.30)),
        (.init(x: rect.width * 0.82, y: rect.height * 0.39), .init(x: rect.width * 0.60, y: rect.height * 0.36)),
        (.init(x: rect.width * 0.83, y: rect.height * 0.33), .init(x: rect.width * 0.60, y: rect.height * 0.33)),
        (.init(x: rect.width * 0.81, y: rect.height * 0.27), .init(x: rect.width * 0.60, y: rect.height * 0.30))
    ]

    for (start, end) in whiskers {
        path.move(to: start)
        path.line(to: end)
    }

    path.stroke()
}

func pngData(from image: NSImage) throws -> Data {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to render PNG data"])
    }

    return data
}
