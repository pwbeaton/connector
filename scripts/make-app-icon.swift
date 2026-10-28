// Draws the app icon: a folded ribbon forming an "S" on a dark tile.
// The ribbon enters from the upper right, runs left, folds down and to the right,
// folds again, and runs off the left edge. Fold creases follow real paper-fold
// geometry (each crease joins where the two strips' edges cross).
// Colors follow the app's three scores: Recovery green, Effort blue, Sleep violet.
//   swift scripts/make-app-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.translateBy(x: 0, y: size)
context.scaleBy(x: 1, y: -1)   // y grows downward

// MARK: Background
let background = CGGradient(colorsSpace: space, colors: [rgb(0x18202B), rgb(0x0B0F15), rgb(0x05070A)] as CFArray,
                            locations: [0, 0.55, 1])!
context.drawLinearGradient(background, start: CGPoint(x: size * 0.85, y: 0), end: CGPoint(x: size * 0.15, y: size), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
let glow = CGGradient(colorsSpace: space, colors: [rgb(0x2EA8FF, 0.14), rgb(0x2EA8FF, 0)] as CFArray, locations: [0, 1])!
context.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 512), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 512), endRadius: 560, options: [])

// MARK: Geometry
let center = CGPoint(x: 512, y: 512)
let width: CGFloat = 200          // ribbon width
let angle: CGFloat = 72 * .pi / 180   // diagonal run, below horizontal
let topY: CGFloat = 206           // top edge of the upper band
let bleed: CGFloat = 80

let direction = CGPoint(x: cos(angle), y: sin(angle))
let lowerLeftNormal = CGPoint(x: -sin(angle), y: cos(angle))

func add(_ a: CGPoint, _ b: CGPoint, _ k: CGFloat = 1) -> CGPoint { CGPoint(x: a.x + b.x * k, y: a.y + b.y * k) }
func rotated(_ p: CGPoint) -> CGPoint { CGPoint(x: 2 * center.x - p.x, y: 2 * center.y - p.y) }
/// Where the line through `origin` along `direction` reaches height `y`.
func onLine(_ origin: CGPoint, atY y: CGFloat) -> CGPoint {
    let t = (y - origin.y) / direction.y
    return add(origin, direction, t)
}

// The diagonal strip is centered on the tile; its two edges:
let outerEdge = add(center, lowerLeftNormal, width / 2)    // lower-left edge
let innerEdge = add(center, lowerLeftNormal, -width / 2)   // upper-right edge

// Fold 1 (upper left): outer corner on the band's top edge, inner corner on its bottom edge.
let fold1Outer = onLine(outerEdge, atY: topY)
let fold1Inner = onLine(innerEdge, atY: topY + width)
// Fold 2 is fold 1 turned 180° around the center.
let fold2Outer = rotated(fold1Outer)
let fold2Inner = rotated(fold1Inner)

func polygon(_ points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: points)
    path.closeSubpath()
    return path
}

let topBand = polygon([CGPoint(x: size + bleed, y: topY), fold1Outer, fold1Inner, CGPoint(x: size + bleed, y: topY + width)])
let diagonal = polygon([fold1Outer, fold1Inner, fold2Outer, fold2Inner])
let bottomBand = polygon([CGPoint(x: -bleed, y: size - topY), fold2Outer, fold2Inner, CGPoint(x: -bleed, y: size - topY - width)])

// MARK: Drawing helpers
func fill(_ path: CGPath, colors: [CGColor], from start: CGPoint, to end: CGPoint) {
    context.saveGState()
    context.addPath(path)
    context.clip()
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
}

/// Darkens a face toward a crease, so the fold reads as a turn in the paper.
func creaseShade(_ path: CGPath, crease a: CGPoint, _ b: CGPoint, toward inside: CGPoint, depth: CGFloat, alpha: CGFloat) {
    let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    // Unit normal to the crease, pointing into the face.
    var n = CGPoint(x: -(b.y - a.y), y: b.x - a.x)
    let length = hypot(n.x, n.y)
    n = CGPoint(x: n.x / length, y: n.y / length)
    if (inside.x - mid.x) * n.x + (inside.y - mid.y) * n.y < 0 { n = CGPoint(x: -n.x, y: -n.y) }
    context.saveGState()
    context.addPath(path)
    context.clip()
    let shade = CGGradient(colorsSpace: space, colors: [rgb(0x000000, alpha), rgb(0x000000, 0)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(shade, start: mid, end: add(mid, n, depth), options: [.drawsBeforeStartLocation])
    context.restoreGState()
}

func centroid(_ points: [CGPoint]) -> CGPoint {
    CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count), y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
}

// MARK: Shadow under the whole ribbon
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -18), blur: 44, color: rgb(0x000000, 0.55))
context.beginTransparencyLayer(auxiliaryInfo: nil)
for path in [topBand, diagonal, bottomBand] {
    context.addPath(path)
    context.setFillColor(rgb(0x000000))
    context.fillPath()
}
context.endTransparencyLayer()
context.restoreGState()

// MARK: Faces
// Top band (front face): Recovery green brightening toward the right edge.
fill(topBand, colors: [rgb(0x0FB868), rgb(0x16E07F), rgb(0x5CF0A6)],
     from: CGPoint(x: fold1Outer.x, y: topY), to: CGPoint(x: size, y: topY))
// Diagonal (the back of the ribbon after the first fold): Effort blue, a touch deeper.
fill(diagonal, colors: [rgb(0x1E8FE6), rgb(0x2EA8FF), rgb(0x1773C9)], from: fold1Outer, to: fold2Outer)
// Bottom band (front again after the second fold): Sleep violet, fading darker to the left edge.
fill(bottomBand, colors: [rgb(0xA89AFF), rgb(0x8F7BFF), rgb(0x5E4BD6)],
     from: CGPoint(x: fold2Outer.x, y: size - topY), to: CGPoint(x: 0, y: size - topY))

// Crease shading: each face darkens slightly where it turns under the next.
let topPts = [CGPoint(x: size, y: topY), fold1Outer, fold1Inner, CGPoint(x: size, y: topY + width)]
let diagPts = [fold1Outer, fold1Inner, fold2Outer, fold2Inner]
let bottomPts = [CGPoint(x: 0, y: size - topY), fold2Outer, fold2Inner, CGPoint(x: 0, y: size - topY - width)]
creaseShade(diagonal, crease: fold1Outer, fold1Inner, toward: centroid(diagPts), depth: 150, alpha: 0.38)
creaseShade(diagonal, crease: fold2Outer, fold2Inner, toward: centroid(diagPts), depth: 150, alpha: 0.38)
creaseShade(topBand, crease: fold1Outer, fold1Inner, toward: centroid(topPts), depth: 90, alpha: 0.16)
creaseShade(bottomBand, crease: fold2Outer, fold2Inner, toward: centroid(bottomPts), depth: 90, alpha: 0.16)

// A thin light line on each crease, where the paper catches the light.
context.saveGState()
context.setLineCap(.round)
context.setLineWidth(3)
context.setStrokeColor(rgb(0xFFFFFF, 0.28))
context.strokeLineSegments(between: [fold1Outer, fold1Inner, fold2Outer, fold2Inner])
context.restoreGState()

let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print("Wrote \(output)")
