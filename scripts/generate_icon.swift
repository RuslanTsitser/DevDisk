import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = URL(filePath: CommandLine.arguments.dropFirst().first ?? "DevDisk/Assets.xcassets/AppIcon.appiconset")
let sizes = [16, 32, 64, 128, 256, 512, 1024]

for size in sizes {
    guard let bitmapContext = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { fatalError("Could not create bitmap context") }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmapContext, flipped: false)
    NSGraphicsContext.current?.imageInterpolation = .high
    let scale = CGFloat(size) / 1024
    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
        NSRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
    }

    let background = NSBezierPath(rect: rect(0, 0, 1024, 1024))
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
    guard let image = bitmapContext.makeImage() else { fatalError("Could not create icon image") }
    let destinationURL = output.appending(path: "icon_\(size).png") as CFURL
    guard let destination = CGImageDestinationCreateWithURL(
        destinationURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else { fatalError("Could not create PNG destination") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not encode icon") }
}
