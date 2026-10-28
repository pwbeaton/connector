// Draws Pluto's app icon ("Balance" from the redesign spec): a navy 1024 tile with a
// 600 pt circle split at 45°, a 40 pt gap, teal over light.
//   swift scripts/make-app-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.translateBy(x: 0, y: size)
context.scaleBy(x: 1, y: -1) // y grows downward

context.setFillColor(rgb(0x0C1B26))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

let center = CGPoint(x: 512, y: 512)
let radius: CGFloat = 300
let halfGap: CGFloat = 20
let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

// The split runs from lower left to upper right. Each half is the circle clipped to the
// side of a line offset 20 pt from the diagonal.
func half(color: UInt32, upperLeft: Bool) {
    context.saveGState()
    context.addEllipse(in: circle)
    context.clip()
    let shift = (upperLeft ? -halfGap : halfGap) / sqrt(2)
    let path = CGMutablePath()
    // A big triangle on one side of the diagonal x + y = 1024 (moved by the gap).
    if upperLeft {
        path.addLines(between: [CGPoint(x: -2000, y: 3024), CGPoint(x: 3024, y: -2000), CGPoint(x: -2000, y: -2000)])
    } else {
        path.addLines(between: [CGPoint(x: -2000, y: 3024), CGPoint(x: 3024, y: -2000), CGPoint(x: 3024, y: 3024)])
    }
    path.closeSubpath()
    context.translateBy(x: shift, y: shift)
    context.addPath(path)
    context.setFillColor(rgb(color))
    context.fillPath()
    context.restoreGState()
}
half(color: 0x3CC2B4, upperLeft: true)
half(color: 0xEEF2F4, upperLeft: false)

let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print("Wrote \(output)")
