import SwiftUI

/// Pluto's signature readout: a ruler of thin ticks (minor and major) with the filled part
/// colored, optional tinted bands (a target range), and markers (today, yesterday, a goal).
/// Drawn in one Canvas so hundreds of ticks stay cheap. Geometry follows the design spec:
/// ticks are 2 pt wide, markers 4 pt (dashed ones 2 pt).
struct TickScale: View {
    struct Ticks {
        var divisions: Int
        var top: CGFloat
        var height: CGFloat
    }

    struct Band {
        var from: Double
        var to: Double
        var color: Color
        var top: CGFloat
        var height: CGFloat
        var radius: CGFloat = 0
        /// Small label centered above the band.
        var label: String?
        var labelColor: Color = Theme.textMuted
    }

    struct Marker {
        enum LabelPlacement { case center, trailing, leading }

        var value: Double
        var color: Color
        var dashed = false
        var top: CGFloat = -4
        var height: CGFloat = 48
        var label: String?
        var labelColor: Color = Theme.textMuted
        var labelWeight: Font.Weight = .regular
        var labelPlacement = LabelPlacement.center
        /// Top of the label relative to the ticks, as in the spec (`top: -20px`). Defaults to
        /// just above the marker.
        var labelTop: CGFloat?
    }

    struct Line {
        var top: CGFloat
        var height: CGFloat
        var color: Color
    }

    let range: ClosedRange<Double>
    var minor: Ticks
    var major: Ticks?
    /// Ticks at or below this value take `fillColor`.
    var fill: Double?
    var fillColor: Color = Theme.teal
    /// Whether major ticks inside the fill are colored too.
    var fillsMajor = true
    var minorColor: Color = Theme.tickMinor
    var majorColor: Color = Theme.tickMajor
    var bands: [Band] = []
    var line: Line?
    var markers: [Marker] = []
    /// Height of the tick area (labels sit above it, axis below).
    var height: CGFloat = 40
    /// Room reserved above the ticks for marker and band labels.
    var labelRoom: CGFloat = 0
    var axis: [(value: Double, label: String)] = []
    /// Space between the ticks and the axis labels (10 in most of the spec, 8 under Recovery).
    var axisGap: CGFloat = 10
    var axisColor: Color = Theme.textMuted

    var body: some View {
        VStack(alignment: .leading, spacing: axis.isEmpty ? 0 : axisGap) {
            Canvas { context, size in
                draw(in: &context, width: size.width)
            }
            .frame(height: height + labelRoom)
            if !axis.isEmpty {
                axisLabels.frame(height: 14)
            }
        }
        .accessibilityHidden(true)
    }

    private func x(_ value: Double, width: CGFloat) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        let fraction = span > 0 ? (value - range.lowerBound) / span : 0
        return CGFloat(min(1, max(0, fraction))) * (width - 2)
    }

    private func draw(in context: inout GraphicsContext, width: CGFloat) {
        let origin = labelRoom
        for band in bands {
            let left = x(band.from, width: width), right = x(band.to, width: width) + 2
            let rect = CGRect(x: left, y: origin + band.top, width: max(0, right - left), height: band.height)
            context.fill(Path(roundedRect: rect, cornerRadius: band.radius), with: .color(band.color))
            if let label = band.label {
                context.draw(Text(label).font(.mono(10)).foregroundStyle(band.labelColor),
                             at: CGPoint(x: (left + right) / 2, y: origin + band.top - 11.5), anchor: .center)
            }
        }
        let fillX = fill.map { x($0, width: width) }
        func drawTicks(_ ticks: Ticks, color: Color, fillable: Bool) {
            guard ticks.divisions > 0 else { return }
            for index in 0...ticks.divisions {
                let tickX = CGFloat(index) / CGFloat(ticks.divisions) * (width - 2)
                let filled = fillable && fillX.map { tickX <= $0 + 0.5 } == true
                context.fill(Path(CGRect(x: tickX, y: origin + ticks.top, width: 2, height: ticks.height)),
                             with: .color(filled ? fillColor : color))
            }
        }
        drawTicks(minor, color: minorColor, fillable: true)
        if let major { drawTicks(major, color: majorColor, fillable: fillsMajor) }
        if let line {
            context.fill(Path(CGRect(x: 0, y: origin + line.top, width: width - 2, height: line.height)), with: .color(line.color))
        }
        for marker in markers {
            let center = x(marker.value, width: width) + 1
            if marker.dashed {
                var y = origin + marker.top
                while y < origin + marker.top + marker.height {
                    context.fill(Path(CGRect(x: center - 1, y: y, width: 2, height: 3)), with: .color(marker.color))
                    y += 6
                }
            } else {
                let rect = CGRect(x: center - 2, y: origin + marker.top, width: 4, height: marker.height)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(marker.color))
            }
            if let label = marker.label {
                let text = Text(label).font(.mono(10, marker.labelWeight)).foregroundStyle(marker.labelColor)
                let y = origin + (marker.labelTop ?? marker.top - 15.5) + 6.5
                switch marker.labelPlacement {
                case .center: context.draw(text, at: CGPoint(x: center, y: y), anchor: .center)
                case .trailing: context.draw(text, at: CGPoint(x: center + 6, y: y), anchor: .leading)
                case .leading: context.draw(text, at: CGPoint(x: center - 6, y: y), anchor: .trailing)
                }
            }
        }
    }

    private var axisLabels: some View {
        GeometryReader { proxy in
            ForEach(Array(axis.enumerated()), id: \.offset) { index, entry in
                let position = x(entry.value, width: proxy.size.width)
                Text(entry.label)
                    .font(.mono(10))
                    .foregroundStyle(axisColor)
                    .fixedSize()
                    .position(x: labelX(index: index, position: position, width: proxy.size.width, label: entry.label), y: 7)
            }
        }
    }

    /// The first label hangs off its tick to the right, the last to the left, the rest are centered.
    private func labelX(index: Int, position: CGFloat, width: CGFloat, label: String) -> CGFloat {
        let approximate = CGFloat(label.count) * 6
        if index == 0 { return approximate / 2 }
        if index == axis.count - 1 { return width - approximate / 2 }
        return position + 1
    }
}

/// A number with small unit suffixes: "7h 2m", "52 ms", "61 min".
struct UnitNumber: View {
    /// Alternating value and unit parts, e.g. [("7", "h"), ("2", "m")].
    let parts: [(value: String, unit: String?)]
    var size: CGFloat = 28
    var width: Double = 75
    var color: Color = Theme.textPrimary
    var unitColor: Color = Theme.textMuted
    var unitSize: CGFloat = 13

    var body: some View {
        parts.enumerated().reduce(Text("")) { text, element in
            let (index, part) = element
            var result = text + Text(part.value).font(.archivo(size, .semibold, width: width)).foregroundStyle(color)
            if let unit = part.unit {
                let lead = index == parts.count - 1 && parts.count == 1 ? "\u{2009}" : ""
                result = result + Text(lead + unit + (index < parts.count - 1 ? " " : ""))
                    .font(.archivo(unitSize, .medium)).foregroundStyle(unitColor)
            }
            return result
        }
        .lineLimit(1)
        .fixedSize()
        .lineBox(1, size: size)
    }

    /// "7h 2m" from minutes.
    static func duration(minutes: Int) -> [(value: String, unit: String?)] {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return [("\(rest)", "m")] }
        return [("\(hours)", "h"), ("\(rest)", "m")]
    }
}

/// A small triangle: ▼ for down, ▲ for up.
struct DeltaArrow: View {
    let down: Bool
    var color: Color = Theme.effort

    var body: some View {
        Canvas { context, size in
            var path = Path()
            if down {
                path.move(to: CGPoint(x: 1, y: 2)); path.addLine(to: CGPoint(x: 9, y: 2)); path.addLine(to: CGPoint(x: 5, y: 8))
            } else {
                path.move(to: CGPoint(x: 1, y: 8)); path.addLine(to: CGPoint(x: 9, y: 8)); path.addLine(to: CGPoint(x: 5, y: 2))
            }
            path.closeSubpath()
            context.fill(path, with: .color(color))
        }
        .frame(width: 10, height: 10)
        .accessibilityHidden(true)
    }
}

/// Pluto's mark: a circle split at 45° with a gap, teal over light.
struct PlutoMark: View {
    var size: CGFloat = 40
    var upper: Color = Color(hex: 0x3CC2B4)
    var lower: Color = Color(hex: 0xEEF2F4)

    var body: some View {
        Canvas { context, canvas in
            let scale = canvas.width / 600
            let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let radius = 300 * scale
            let gap = 20 * scale
            for (offset, color) in [(-gap, upper), (gap, lower)] {
                var half = Path()
                half.addArc(center: center, radius: radius, startAngle: .degrees(-45), endAngle: .degrees(135),
                            clockwise: offset < 0)
                half.closeSubpath()
                let shift = offset / sqrt(2)
                context.fill(half.applying(CGAffineTransform(translationX: shift, y: shift))
                    .intersection(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                         width: radius * 2, height: radius * 2))),
                             with: .color(color))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
