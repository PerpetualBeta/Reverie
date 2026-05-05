#!/usr/bin/env swift

import AppKit
import CoreGraphics

let brandBlue = NSColor(red: 0x00/255.0, green: 0x40/255.0, blue: 0x80/255.0, alpha: 1.0)

// Hypotrochoid sampling for the icon motif. (R, r, d) tuned by eye for a
// pleasing seven-pointed rose with internal lobes — same math the saver uses.
func hypotrochoid(R: CGFloat, r: CGFloat, d: CGFloat, samples: Int) -> [CGPoint] {
    let totalT: CGFloat = 14 * .pi
    var pts: [CGPoint] = []
    pts.reserveCapacity(samples)
    let k = (R - r) / r
    for i in 0...samples {
        let t = totalT * CGFloat(i) / CGFloat(samples)
        let x = (R - r) * cos(t) + d * cos(k * t)
        let y = (R - r) * sin(t) - d * sin(k * t)
        pts.append(CGPoint(x: x, y: y))
    }
    return pts
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let s = size
    let cx = s / 2
    let cy = s / 2

    // Brand-blue rounded background.
    let bgRect = NSRect(x: s * 0.04, y: s * 0.04, width: s * 0.92, height: s * 0.92)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: s * 0.18, yRadius: s * 0.18)
    brandBlue.setFill()
    bgPath.fill()

    // Subtle radial gradient for depth.
    let space = CGColorSpaceCreateDeviceRGB()
    let gradColors = [
        NSColor(white: 1.0, alpha: 0.10).cgColor,
        NSColor(white: 0.0, alpha: 0.10).cgColor
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: space, colors: gradColors, locations: [0.0, 1.0]) {
        ctx.saveGState()
        ctx.addPath(bgPath.cgPath)
        ctx.clip()
        ctx.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: cx, y: cy + s * 0.12),
            startRadius: 0,
            endCenter: CGPoint(x: cx, y: cy),
            endRadius: s * 0.55,
            options: []
        )
        ctx.restoreGState()
    }

    // Hypotrochoid motif. Scale chosen so the curve fills ~74 % of the icon.
    ctx.saveGState()
    ctx.addPath(bgPath.cgPath)
    ctx.clip()

    let motifSize = s * 0.36
    let R: CGFloat = motifSize * 1.0
    let r: CGFloat = motifSize * 0.30
    let d: CGFloat = motifSize * 0.22
    let pts = hypotrochoid(R: R, r: r, d: d, samples: 1400)

    // Translate to centre, build CGMutablePath
    let path = CGMutablePath()
    for (i, p) in pts.enumerated() {
        let pt = CGPoint(x: p.x + cx, y: p.y + cy)
        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
    }

    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // Wide soft halo behind the curve.
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.18).cgColor)
    ctx.setLineWidth(max(s * 0.030, 1.2))
    ctx.addPath(path)
    ctx.strokePath()

    // Main stroke.
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.98).cgColor)
    ctx.setLineWidth(max(s * 0.014, 0.8))
    ctx.addPath(path)
    ctx.strokePath()

    ctx.restoreGState()

    image.unlockFocus()
    return image
}

extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        let points = UnsafeMutablePointer<NSPoint>.allocate(capacity: 3)
        defer { points.deallocate() }
        for i in 0..<elementCount {
            let element = self.element(at: i, associatedPoints: points)
            switch element {
            case .moveTo:           path.move(to: points[0])
            case .lineTo:           path.addLine(to: points[0])
            case .curveTo:          path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .cubicCurveTo:     path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo: path.addQuadCurve(to: points[1], control: points[0])
            case .closePath:        path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
}

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]

let scriptDir = CommandLine.arguments[0].components(separatedBy: "/").dropLast().joined(separator: "/")
let iconsetDir = (scriptDir.isEmpty ? "." : scriptDir) + "/Resources/Reverie.iconset"
let fm = FileManager.default
try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

for (size, name) in sizes {
    let image = drawIcon(size: CGFloat(size))
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else { continue }
    try! png.write(to: URL(fileURLWithPath: iconsetDir + "/" + name))
    print("  \(name) (\(size)x\(size))")
}

let icnsPath = (scriptDir.isEmpty ? "." : scriptDir) + "/Resources/AppIcon.icns"
let result = Process()
result.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
result.arguments = ["-c", "icns", iconsetDir, "-o", icnsPath]
try! result.run()
result.waitUntilExit()
print("  AppIcon.icns")
print("Done.")
