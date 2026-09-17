//
//  make_icon.swift
//  Focus Deck — synthwave app icon generator (Miami Dusk palette).
//
//  Standalone, re-runnable:  cd <repo> && swift scripts/make_icon.swift
//  Writes assets/AppIcon-1024.png, then assets/AppIcon.iconset/* via sips,
//  then assets/AppIcon.icns via iconutil. Any failure exits non-zero.
//
import AppKit
import CoreGraphics
import Foundation

// MARK: - Failure + logging

func die(_ message: String) -> Never {
    let text = "make_icon: ERROR: " + message + "\n"
    FileHandle.standardError.write(text.data(using: .utf8)!)
    exit(1)
}

func log(_ message: String) {
    print("make_icon: " + message)
}

// MARK: - Colour helpers (Miami Dusk, mirrors Sources/FocusDeckKit/CoverDesign.swift)

func srgb(_ hex: String, _ alpha: CGFloat = 1) -> CGColor {
    var s = hex
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let value = UInt32(s, radix: 16) else { die("bad hex colour \(hex)") }
    let r = CGFloat((value >> 16) & 0xFF) / 255
    let g = CGFloat((value >> 8) & 0xFF) / 255
    let b = CGFloat(value & 0xFF) / 255
    return CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!

let skyTopHex = "140A2E"
let skyMidHex = "5B1170"
let skyBottomHex = "FF3D7F"
let sunTopHex = "FFE66D"
let sunBottomHex = "FF2E63"
let gridHex = "00E5FF"
let ridgeHex = "1B0B33"
let accentHex = "FF2E97"

let skyTop = srgb(skyTopHex)
let skyMid = srgb(skyMidHex)
let skyBottom = srgb(skyBottomHex)
let sunTop = srgb(sunTopHex)
let sunBottom = srgb(sunBottomHex)
let gridColor = srgb(gridHex)
let ridgeColor = srgb(ridgeHex)
let accent = srgb(accentHex)

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    let colors = stops.map { $0.1 } as CFArray
    let locations = stops.map { $0.0 }
    guard let g = CGGradient(colorsSpace: space, colors: colors, locations: locations) else {
        die("cannot build gradient")
    }
    return g
}

// MARK: - Canvas + composition constants

let canvas: CGFloat = 1024
let W = canvas
let H = canvas
let margin: CGFloat = 40                                  // transparent Dock margin
let box = CGRect(x: margin, y: margin, width: W - 2 * margin, height: H - 2 * margin)
let cornerRadius: CGFloat = 212                           // ~230/1024 scaled to the 944px box
let horizonY: CGFloat = 620
let floorBottom = box.maxY
let sunCenter = CGPoint(x: 512, y: 412)
let sunRadius: CGFloat = 214

// MARK: - Sun layer (own context so slit cuts can use .clear)

func sunLayer() -> CGImage {
    guard let c = CGContext(data: nil, width: Int(canvas), height: Int(canvas),
                            bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        die("cannot create sun layer context")
    }
    func Y(_ topDown: CGFloat) -> CGFloat { canvas - topDown }   // bottom-left origin inside layer
    let cy = Y(sunCenter.y)
    let center = CGPoint(x: sunCenter.x, y: cy)

    // Soft magenta bloom behind the disc.
    let bloom = gradient([
        (0.00, accent.copy(alpha: 0.42)!),
        (0.45, srgb("FF3D7F", 0.20)),
        (1.00, accent.copy(alpha: 0.0)!),
    ])
    c.drawRadialGradient(bloom,
                         startCenter: center, startRadius: sunRadius * 0.80,
                         endCenter: center, endRadius: sunRadius * 1.72,
                         options: [])

    // Sun disc: FFE66D -> FF2E63.
    c.saveGState()
    c.addEllipse(in: CGRect(x: center.x - sunRadius, y: center.y - sunRadius,
                            width: sunRadius * 2, height: sunRadius * 2))
    c.clip()
    let disc = gradient([
        (0.00, sunTop),
        (0.34, srgb("FFB44E")),
        (0.68, srgb("FF6A45")),
        (1.00, sunBottom),
    ])
    c.drawLinearGradient(disc,
                         start: CGPoint(x: 0, y: center.y + sunRadius),
                         end: CGPoint(x: 0, y: center.y - sunRadius),
                         options: [])
    c.restoreGState()

    // Horizontal slit cuts, thicker toward the bottom of the disc.
    // Clipped to the disc so the cuts never spill onto the sky.
    c.setBlendMode(.clear)
    c.saveGState()
    c.addEllipse(in: CGRect(x: center.x - sunRadius * 1.02, y: center.y - sunRadius * 1.02,
                            width: sunRadius * 2.04, height: sunRadius * 2.04))
    c.clip()
    var slitTop = sunCenter.y
    var index = 0
    while slitTop < sunCenter.y + sunRadius {
        let thickness = 4.2 + CGFloat(index) * 3.8
        let gap = 17.0 + CGFloat(index) * 2.2
        c.fill(CGRect(x: sunCenter.x - sunRadius * 1.4,
                      y: Y(slitTop) - thickness,
                      width: sunRadius * 2.8,
                      height: thickness))
        slitTop += thickness + gap
        index += 1
    }
    c.restoreGState()
    c.setBlendMode(.normal)

    guard let image = c.makeImage() else { die("cannot rasterise sun layer") }
    return image
}

// MARK: - Ridge silhouette

let ridgeControl: [(CGFloat, CGFloat)] = [
    (40, 16), (105, 33), (175, 46), (250, 27), (330, 57), (410, 35),
    (492, 20), (575, 29), (655, 51), (735, 25), (815, 39), (905, 19), (984, 25),
]

func ridgeHeight(_ x: CGFloat) -> CGFloat {
    var lower = ridgeControl[0]
    var upper = ridgeControl[ridgeControl.count - 1]
    for i in 0..<(ridgeControl.count - 1) {
        if x >= ridgeControl[i].0 && x <= ridgeControl[i + 1].0 {
            lower = ridgeControl[i]
            upper = ridgeControl[i + 1]
            break
        }
    }
    let span = max(1, upper.0 - lower.0)
    let t = min(1, max(0, (x - lower.0) / span))
    let s = (1 - cos(t * CGFloat.pi)) / 2
    var height = lower.1 + (upper.1 - lower.1) * s
    height += 2.6 * sin(x * 0.045) + 1.6 * sin(x * 0.131)
    return max(4, height)
}

// MARK: - Main render

guard let ctx = CGContext(data: nil, width: Int(canvas), height: Int(canvas),
                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    die("cannot create main bitmap context")
}
ctx.setShouldAntialias(true)
ctx.interpolationQuality = .high
// Flip to a top-down coordinate system so the layout reads like the design.
ctx.translateBy(x: 0, y: H)
ctx.scaleBy(x: 1, y: -1)

let shapePath = CGPath(roundedRect: box, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

// Draw everything clipped to the icon shape.
ctx.saveGState()
ctx.addPath(shapePath)
ctx.clip()

// 1. Sky.
let sky = gradient([
    (0.00, skyTop),
    (0.34, srgb("300B4E")),
    (0.64, srgb("4B0F63")),
    (0.84, srgb("8E1870")),
    (1.00, skyBottom),
])
ctx.drawLinearGradient(sky,
                       start: CGPoint(x: box.midX, y: box.minY),
                       end: CGPoint(x: box.midX, y: horizonY),
                       options: [])
// A whisper of star dust, high in the sky only.
ctx.setBlendMode(.plusLighter)
for i in 0..<54 {
    let fx = CGFloat((i &* 2654435761) % 1000) / 1000
    let fy = CGFloat((i &* 40503) % 1000) / 1000
    let x = box.minX + fx * box.width
    let y = box.minY + pow(fy, 1.6) * (horizonY - box.minY) * 0.62
    let r: CGFloat = 1.0 + CGFloat((i % 3)) * 0.7
    let a = 0.06 + 0.17 * (1.0 - fy)
    ctx.setFillColor(srgb("FFFFFF", a))
    ctx.fillEllipse(in: CGRect(x: x, y: y, width: r * 2, height: r * 2))
}
ctx.setBlendMode(.normal)

// 2. Horizon glow (elliptical, additive).
ctx.saveGState()
ctx.setBlendMode(.plusLighter)
ctx.translateBy(x: box.midX, y: horizonY)
ctx.scaleBy(x: 1, y: 0.28)
let halo = gradient([
    (0.00, srgb("FFE7F6", 0.20)),
    (0.22, srgb("FFB36A", 0.17)),
    (0.48, srgb("FF3D7F", 0.15)),
    (1.00, srgb("FF2E97", 0.0)),
])
ctx.drawRadialGradient(halo,
                       startCenter: .zero, startRadius: 0,
                       endCenter: .zero, endRadius: 760,
                       options: [])
ctx.restoreGState()

// 3. Sun (own layer, with slit cuts).
let sun = sunLayer()
ctx.saveGState()
ctx.translateBy(x: 0, y: H)
ctx.scaleBy(x: 1, y: -1)
ctx.draw(sun, in: CGRect(x: 0, y: 0, width: W, height: H))
ctx.restoreGState()

// 4. Floor.
let floor = gradient([
    (0.00, srgb("3A0B4E")),
    (0.30, srgb("1D0736")),
    (1.00, srgb("08040F")),
])
ctx.drawLinearGradient(floor,
                       start: CGPoint(x: box.midX, y: horizonY),
                       end: CGPoint(x: box.midX, y: floorBottom),
                       options: [])

// Sun reflection column on the floor.
ctx.saveGState()
ctx.setBlendMode(.plusLighter)
ctx.translateBy(x: box.midX, y: horizonY)
ctx.scaleBy(x: 0.62, y: 3.1)
let reflection = gradient([
    (0.00, srgb("FF9AD0", 0.18)),
    (0.40, accent.copy(alpha: 0.10)!),
    (1.00, accent.copy(alpha: 0.0)!),
])
ctx.drawRadialGradient(reflection,
                       startCenter: .zero, startRadius: 0,
                       endCenter: .zero, endRadius: 150,
                       options: [])
ctx.restoreGState()

// 5. Perspective neon grid, scrolling toward the viewer.
let vanishing = CGPoint(x: box.midX, y: horizonY)
let radiate = CGMutablePath()
let horizontal = CGMutablePath()

for i in -13...13 {
    let f = CGFloat(i)
    let spread = (f == 0) ? 0 : (f < 0 ? -1 : 1) * pow(abs(f), 1.05) * 100
    radiate.move(to: vanishing)
    radiate.addLine(to: CGPoint(x: box.midX + spread, y: floorBottom))
}

let rows = 10
for i in 0..<rows {
    let u = (CGFloat(i) + 0.34) / CGFloat(rows)
    let y = horizonY + (floorBottom - horizonY) * pow(u, 1.95)
    horizontal.move(to: CGPoint(x: box.minX, y: y))
    horizontal.addLine(to: CGPoint(x: box.maxX, y: y))
}

ctx.setLineCap(.round)
ctx.setBlendMode(.plusLighter)
// Wide glow pass.
ctx.setStrokeColor(gridColor.copy(alpha: 0.11)!)
ctx.setLineWidth(9)
ctx.addPath(radiate); ctx.strokePath()
ctx.addPath(horizontal); ctx.strokePath()
// Mid pass.
ctx.setStrokeColor(gridColor.copy(alpha: 0.34)!)
ctx.setLineWidth(3.1)
ctx.addPath(radiate); ctx.strokePath()
ctx.addPath(horizontal); ctx.strokePath()
// Hot core pass.
ctx.setStrokeColor(srgb("CFFBFF", 0.95))
ctx.setLineWidth(1.35)
ctx.addPath(radiate); ctx.strokePath()
ctx.addPath(horizontal); ctx.strokePath()

// 6. Bright horizon line.
ctx.setStrokeColor(gridColor.copy(alpha: 0.16)!)
ctx.setLineWidth(12)
ctx.move(to: CGPoint(x: box.minX, y: horizonY))
ctx.addLine(to: CGPoint(x: box.maxX, y: horizonY))
ctx.strokePath()
ctx.setStrokeColor(srgb("E8FFFF", 0.72))
ctx.setLineWidth(2.8)
ctx.move(to: CGPoint(x: box.minX, y: horizonY))
ctx.addLine(to: CGPoint(x: box.maxX, y: horizonY))
ctx.strokePath()
ctx.setBlendMode(.normal)

// 7. Low ridge / skyline silhouette.
let ridgePath = CGMutablePath()
ridgePath.move(to: CGPoint(x: box.minX, y: horizonY + 9))
var ridgeTop = CGMutablePath()
var rx = box.minX
var first = true
while rx <= box.maxX {
    let y = horizonY + 9 - ridgeHeight(rx)
    ridgePath.addLine(to: CGPoint(x: rx, y: y))
    if first {
        ridgeTop.move(to: CGPoint(x: rx, y: y))
        first = false
    } else {
        ridgeTop.addLine(to: CGPoint(x: rx, y: y))
    }
    rx += 6
}
ridgePath.addLine(to: CGPoint(x: box.maxX, y: horizonY + 9))
ridgePath.closeSubpath()
ctx.setFillColor(ridgeColor)
ctx.addPath(ridgePath)
ctx.fillPath()

// Neon rim light on the ridge crest.
ctx.setBlendMode(.plusLighter)
ctx.setLineCap(.round)
ctx.setStrokeColor(accent.copy(alpha: 0.16)!)
ctx.setLineWidth(7)
ctx.addPath(ridgeTop); ctx.strokePath()
ctx.setStrokeColor(srgb("FF7AC8", 0.78))
ctx.setLineWidth(1.7)
ctx.addPath(ridgeTop); ctx.strokePath()
ctx.setBlendMode(.normal)

// 8. Scanlines.
ctx.setBlendMode(.normal)
ctx.setFillColor(srgb("000000", 0.055))
var sy = box.minY
while sy < box.maxY {
    ctx.fill(CGRect(x: box.minX, y: sy, width: box.width, height: 1.6))
    sy += 4.4
}

// 9. Vignette.
let vignette = gradient([
    (0.00, srgb("000000", 0.0)),
    (0.62, srgb("000000", 0.06)),
    (1.00, srgb("05000F", 0.55)),
])
ctx.drawRadialGradient(vignette,
                       startCenter: CGPoint(x: box.midX, y: box.midY - 40), startRadius: 60,
                       endCenter: CGPoint(x: box.midX, y: box.midY - 40), endRadius: 660,
                       options: [])

ctx.restoreGState()   // drop the shape clip

// 10. Inner light rim + edge definition (gradient stroke following the shape).
ctx.saveGState()
let rimOuter = CGPath(roundedRect: box, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
let rimInner = CGPath(roundedRect: box.insetBy(dx: 7, dy: 7),
                      cornerWidth: max(0, cornerRadius - 7), cornerHeight: max(0, cornerRadius - 7),
                      transform: nil)
let rimRing = CGMutablePath()
rimRing.addPath(rimOuter)
rimRing.addPath(rimInner)
ctx.addPath(rimRing)
ctx.clip(using: .evenOdd)
let rim = gradient([
    (0.00, srgb("FFFFFF", 0.42)),
    (0.30, srgb("FFE9FF", 0.20)),
    (0.62, srgb("FFFFFF", 0.10)),
    (1.00, srgb("FFFFFF", 0.22)),
])
ctx.drawLinearGradient(rim,
                       start: CGPoint(x: box.midX, y: box.minY),
                       end: CGPoint(x: box.midX, y: box.maxY),
                       options: [])
ctx.restoreGState()

// Thin dark edge so the icon separates from light and dark backgrounds alike.
ctx.setStrokeColor(srgb("0A0117", 0.55))
ctx.setLineWidth(1.6)
ctx.addPath(rimOuter)
ctx.strokePath()

// MARK: - Write PNG

guard let image = ctx.makeImage() else { die("cannot rasterise the icon") }

// MARK: - Paths

func repoRoot() -> URL {
    let scriptURL = URL(fileURLWithPath: #filePath)
    let candidate = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
    let fm = FileManager.default
    if fm.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path) {
        return candidate
    }
    return URL(fileURLWithPath: fm.currentDirectoryPath)
}

let root = repoRoot()
let assets = root.appendingPathComponent("assets", isDirectory: true)
let iconset = assets.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let masterPNG = assets.appendingPathComponent("AppIcon-1024.png")
let icns = assets.appendingPathComponent("AppIcon.icns")

let fm = FileManager.default
do {
    try fm.createDirectory(at: assets, withIntermediateDirectories: true)
    if fm.fileExists(atPath: iconset.path) { try fm.removeItem(at: iconset) }
    try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
} catch {
    die("cannot prepare assets directories: \(error.localizedDescription)")
}

guard let pngData = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
    die("PNG encoding failed")
}
do {
    try pngData.write(to: masterPNG)
} catch {
    die("cannot write \(masterPNG.path): \(error.localizedDescription)")
}
log("wrote \(masterPNG.path) (\(Int(canvas))x\(Int(canvas)))")

// MARK: - Shell steps: sips -> iconutil

@discardableResult
func run(_ tool: String, _ arguments: [String], quiet: Bool = false) -> Int32 {
    guard fm.isExecutableFile(atPath: tool) else {
        die("required tool not found: \(tool)")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    if quiet { process.standardOutput = FileHandle.nullDevice }
    do {
        try process.run()
    } catch {
        die("cannot launch \(tool): \(error.localizedDescription)")
    }
    process.waitUntilExit()
    return process.terminationStatus
}

let sips = "/usr/bin/sips"
let iconutil = "/usr/bin/iconutil"
guard fm.isExecutableFile(atPath: iconutil) else {
    die("iconutil not available at \(iconutil); cannot build .icns")
}

let variants: [(name: String, pixels: Int)] = [
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

for variant in variants {
    let out = iconset.appendingPathComponent(variant.name)
    let status = run(sips, ["-z", "\(variant.pixels)", "\(variant.pixels)", masterPNG.path, "--out", out.path], quiet: true)
    if status != 0 {
        die("sips failed (exit \(status)) for \(variant.name)")
    }
    if !fm.fileExists(atPath: out.path) {
        die("sips reported success but \(out.path) is missing")
    }
}
log("wrote \(variants.count) iconset PNGs into \(iconset.path)")

if fm.fileExists(atPath: icns.path) { try? fm.removeItem(at: icns) }
let icnsStatus = run(iconutil, ["-c", "icns", iconset.path, "-o", icns.path])
if icnsStatus != 0 {
    die("iconutil failed (exit \(icnsStatus)) building \(icns.path)")
}
guard fm.fileExists(atPath: icns.path) else {
    die("iconutil reported success but \(icns.path) is missing")
}
log("wrote \(icns.path)")
log("done.")
