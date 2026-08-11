import AppKit
import Foundation

let output = URL(filePath: CommandLine.arguments.dropFirst().first ?? "DevDisk/Assets.xcassets/AppIcon.appiconset")
let sizes = [16, 32, 64, 128, 256, 512, 1024]

for size in sizes {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: size * 4,
        bitsPerPixel: 32
    ) else { fatalError("Could not create bitmap") }

    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    let scale = CGFloat(size) / 1024
    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
        NSRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
    }

    let background = NSBezierPath(roundedRect: rect(42, 42, 940, 940), xRadius: 214 * scale, yRadius: 214 * scale)
    NSGradient(colors: [
        NSColor(red: 0.035, green: 0.067, blue: 0.145, alpha: 1),
        NSColor(red: 0.055, green: 0.15, blue: 0.26, alpha: 1)
    ])!.draw(in: background, angle: -55)

    let layers: [(NSRect, NSColor)] = [
        (rect(170, 245, 684, 150), NSColor(red: 0.12, green: 0.33, blue: 0.48, alpha: 1)),
        (rect(145, 410, 734, 160), NSColor(red: 0.10, green: 0.44, blue: 0.58, alpha: 1)),
        (rect(120, 585, 784, 174), NSColor(red: 0.09, green: 0.57, blue: 0.68, alpha: 1))
    ]
    for (layerRect, color) in layers {
        let layer = NSBezierPath(roundedRect: layerRect, xRadius: 48 * scale, yRadius: 48 * scale)
        color.setFill()
        layer.fill()
        NSColor.white.withAlphaComponent(0.15).setStroke()
        layer.lineWidth = max(1, 4 * scale)
        layer.stroke()
    }

    let code = NSBezierPath()
    code.move(to: NSPoint(x: 424 * scale, y: 678 * scale))
    code.line(to: NSPoint(x: 350 * scale, y: 635 * scale))
    code.line(to: NSPoint(x: 424 * scale, y: 592 * scale))
    code.move(to: NSPoint(x: 600 * scale, y: 678 * scale))
    code.line(to: NSPoint(x: 674 * scale, y: 635 * scale))
    code.line(to: NSPoint(x: 600 * scale, y: 592 * scale))
    code.move(to: NSPoint(x: 548 * scale, y: 700 * scale))
    code.line(to: NSPoint(x: 478 * scale, y: 570 * scale))
    NSColor(red: 0.69, green: 1, blue: 0.88, alpha: 1).setStroke()
    code.lineWidth = max(2, 24 * scale)
    code.lineCapStyle = .round
    code.lineJoinStyle = .round
    code.stroke()

    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode icon")
    }
    try data.write(to: output.appending(path: "icon_\(size).png"), options: .atomic)
}
