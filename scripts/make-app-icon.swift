// Draws the app icon: a dark tile with rounded "stat lines" streaking in from the left,
// in the app's score colors. Run on a Mac:
//   swift scripts/make-app-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// Flip so y grows downward, like a design tool.
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: 1, y: -1)
let full = CGRect(x: 0, y: 0, width: size, height: size)

// Background: near-black with a cool lift toward the top right.
let background = CGGradient(colorsSpace: space, colors: [rgb(0x161C25), rgb(0x0A0D12), rgb(0x050608)] as CFArray,
                            locations: [0, 0.55, 1])!
context.drawLinearGradient(background, start: CGPoint(x: CGFloat(size), y: 0), end: CGPoint(x: 0, y: CGFloat(size)), options: [])

// A soft glow behind the line ends.
let glow = CGGradient(colorsSpace: space, colors: [rgb(0x2EA8FF, 0.16), rgb(0x2EA8FF, 0)] as CFArray, locations: [0, 1])!
context.drawRadialGradient(glow, startCenter: CGPoint(x: 640, y: 512), startRadius: 0,
                           endCenter: CGPoint(x: 640, y: 512), endRadius: 600, options: [])

// The stat lines: Recovery green, Effort blue, Sleep violet, and an amber accent.
struct Line { let y: CGFloat; let end: CGFloat; let height: CGFloat; let color: UInt32 }
let lines = [
    Line(y: 236, end: 800, height: 104, color: 0x16E07F),
    Line(y: 420, end: 930, height: 104, color: 0x2EA8FF),
    Line(y: 604, end: 700, height: 104, color: 0x8F7BFF),
    Line(y: 788, end: 570, height: 104, color: 0xFFC83D),
]

for line in lines {
    let rect = CGRect(x: -line.height, y: line.y - line.height / 2, width: line.end + line.height, height: line.height)
    let path = CGPath(roundedRect: rect, cornerWidth: line.height / 2, cornerHeight: line.height / 2, transform: nil)

    // Glow around the bright end: the last stretch of the bar, drawn with a colored shadow.
    // The shape itself is drawn off the canvas so only its shadow (the glow) lands on the icon.
    let offCanvas: CGFloat = 4000
    let tail = CGRect(x: line.end * 0.72 + offCanvas, y: rect.minY, width: line.end * 0.28, height: line.height)
    context.saveGState()
    context.setShadow(offset: CGSize(width: -offCanvas, height: 0), blur: 48, color: rgb(line.color, 0.6))
    context.addPath(CGPath(roundedRect: tail, cornerWidth: line.height / 2, cornerHeight: line.height / 2, transform: nil))
    context.setFillColor(rgb(line.color))
    context.fillPath()
    context.restoreGState()

    // The bar fades in from the left edge, like a streak.
    context.saveGState()
    context.addPath(path)
    context.clip()
    let streak = CGGradient(colorsSpace: space,
                            colors: [rgb(line.color, 0.45), rgb(line.color, 0.8), rgb(line.color, 1)] as CFArray,
                            locations: [0, 0.3, 0.6])!
    context.drawLinearGradient(streak, start: CGPoint(x: 0, y: line.y), end: CGPoint(x: line.end, y: line.y), options: [])
    context.restoreGState()
}

let image = context.makeImage()!
let url = URL(fileURLWithPath: output)
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print("Wrote \(output)")
