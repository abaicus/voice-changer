// Draws the app icon and writes Resources/AppIcon.icns. Run: swift Scripts/make-icon.swift
import AppKit

func render(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    let scale = CGFloat(size) / 1024
    context.scaleBy(x: scale, y: scale)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
    let space = CGColorSpaceCreateDeviceRGB()

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(shape)
    context.setFillColor(CGColor(red: 0.07, green: 0.05, blue: 0.12, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let background = CGGradient(
        colorsSpace: space,
        colors: [CGColor(red: 0.20, green: 0.13, blue: 0.33, alpha: 1), CGColor(red: 0.05, green: 0.04, blue: 0.09, alpha: 1)] as CFArray,
        locations: [0, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])
    let glow = CGGradient(
        colorsSpace: space,
        colors: [CGColor(red: 1, green: 0.36, blue: 0.62, alpha: 0.28), CGColor(red: 1, green: 0.36, blue: 0.62, alpha: 0)] as CFArray,
        locations: [0, 1])!
    context.drawRadialGradient(
        glow, startCenter: CGPoint(x: 512, y: 512), startRadius: 0, endCenter: CGPoint(x: 512, y: 512), endRadius: 420, options: [])

    let heights: [CGFloat] = [150, 300, 470, 240, 380, 200, 110]
    let width: CGFloat = 54, gap: CGFloat = 34
    let total = CGFloat(heights.count) * width + CGFloat(heights.count - 1) * gap
    let bars = CGMutablePath()
    for (index, height) in heights.enumerated() {
        let x = 512 - total / 2 + CGFloat(index) * (width + gap)
        bars.addRoundedRect(
            in: CGRect(x: x, y: 512 - height / 2, width: width, height: height), cornerWidth: width / 2, cornerHeight: width / 2)
    }
    context.addPath(bars)
    context.clip()
    let accent = CGGradient(
        colorsSpace: space,
        colors: [CGColor(red: 1, green: 0.36, blue: 0.62, alpha: 1), CGColor(red: 0.98, green: 0.62, blue: 0.25, alpha: 1)] as CFArray,
        locations: [0, 1])!
    context.drawLinearGradient(accent, start: CGPoint(x: 220, y: 760), end: CGPoint(x: 800, y: 260), options: [])
    context.restoreGState()

    NSGraphicsContext.current!.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try render(1024).write(to: root.appendingPathComponent("docs/icon.png"))
