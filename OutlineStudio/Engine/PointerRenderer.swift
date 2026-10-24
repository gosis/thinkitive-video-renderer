//
//  PointerRenderer.swift
//  OutlineStudio
//

import CoreGraphics
import SwiftUI

/// Draws a `PenPointer` at the tip of a partly traced path.
///
/// Glows are radial gradients rather than shadows, so they look the same in the
/// preview and the full-resolution export.
enum PointerRenderer {
    /// Draws `style` where `path` has been traced to `progress` (0–1).
    static func draw(_ style: PenPointer, along path: Path, progress: CGFloat, time: Double,
                     color: CGColor, lineWidth: CGFloat, fontSize: CGFloat, in context: CGContext) {
        guard style != .off, progress > 0, progress < 1,
              let tip = path.trimmedPath(from: 0, to: progress).currentPoint else { return }

        switch style {
        case .off:
            break
        case .dot:
            glow(at: tip, radius: max(lineWidth * 3.2, fontSize * 0.2), color: color, alpha: 0.7, in: context)
            disc(at: tip, radius: max(lineWidth * 0.85, fontSize * 0.035), in: context)
        case .spark:
            let accent = highlight(for: color)
            glow(at: tip, radius: fontSize * 0.3, color: accent, alpha: 0.7, in: context)
            let pulse = 1 + 0.15 * sin(time * 12)
            star(at: tip, radius: fontSize * 0.19 * pulse, rotation: time * 1.6, color: accent, in: context)
            star(at: tip, radius: fontSize * 0.09 * pulse, rotation: time * 1.6, color: CGColor(gray: 1, alpha: 1), in: context)
        case .comet:
            let accent = highlight(for: color)
            trail(of: path, to: progress, length: fontSize * 1.2, color: accent, lineWidth: lineWidth, in: context)
            glow(at: tip, radius: max(lineWidth * 2.8, fontSize * 0.18), color: accent, alpha: 0.85, in: context)
            disc(at: tip, radius: max(lineWidth * 0.75, fontSize * 0.032), in: context)
        case .pencil:
            pencil(at: tip, length: fontSize * 1.05, wobble: sin(time * 9) * 0.05, in: context)
        }
    }

    // MARK: Pieces

    private static func glow(at point: CGPoint, radius: CGFloat, color: CGColor, alpha: CGFloat, in context: CGContext) {
        let colors = [color.copy(alpha: alpha) ?? color, color.copy(alpha: 0) ?? color] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors,
                                        locations: [0, 1]) else { return }
        context.drawRadialGradient(gradient, startCenter: point, startRadius: 0,
                                   endCenter: point, endRadius: radius, options: [])
    }

    private static func disc(at point: CGPoint, radius: CGFloat, in context: CGContext) {
        context.saveGState()
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        context.restoreGState()
    }

    /// A four-point twinkle.
    private static func star(at point: CGPoint, radius: CGFloat, rotation: Double, color: CGColor, in context: CGContext) {
        let star = CGMutablePath()
        for i in 0..<8 {
            let angle = rotation + Double(i) * .pi / 4
            let r = i.isMultiple(of: 2) ? radius : radius * 0.22
            let p = CGPoint(x: point.x + r * CGFloat(cos(angle)), y: point.y + r * CGFloat(sin(angle)))
            i == 0 ? star.move(to: p) : star.addLine(to: p)
        }
        star.closeSubpath()
        context.saveGState()
        context.setFillColor(color)
        context.addPath(star)
        context.fillPath()
        context.restoreGState()
    }

    /// A glowing tail along the last stretch of the stroke, brightest at the tip.
    private static func trail(of path: Path, to progress: CGFloat, length: CGFloat, color: CGColor,
                              lineWidth: CGFloat, in context: CGContext) {
        let total = approximateLength(of: path)
        guard total > 0 else { return }
        let span = min(length / total, progress)
        let pieces = 8
        context.saveGState()
        // Flat ends so the overlapping pieces blend into one tapering tail instead of beads
        context.setLineCap(.butt)
        for i in 0..<pieces {
            let from = progress - span * CGFloat(pieces - i) / CGFloat(pieces)
            let to = progress - span * CGFloat(pieces - i - 1) / CGFloat(pieces)
            let strength = CGFloat(i + 1) / CGFloat(pieces)
            context.setStrokeColor(color.copy(alpha: 0.55 * strength) ?? color)
            context.setLineWidth(lineWidth * (1 + 2.2 * strength))
            context.addPath(path.trimmedPath(from: max(from, 0), to: to).cgPath)
            context.strokePath()
        }
        context.restoreGState()
    }

    /// A small pencil whose point sits on the tip, leaning up and to the right.
    private static func pencil(at point: CGPoint, length: CGFloat, wobble: Double, in context: CGContext) {
        let width = length * 0.17
        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        context.rotate(by: CGFloat(-0.9 + wobble))

        // Built along +x from the point: graphite, sharpened wood, body, ferrule, eraser
        func band(_ from: CGFloat, _ to: CGFloat, _ hex: UInt32) {
            context.setFillColor(rgb(hex))
            context.fill(CGRect(x: length * from, y: -width / 2, width: length * (to - from), height: width))
        }
        band(0.24, 0.84, 0xFF6A4D)
        context.setFillColor(rgb(0xE0482B))
        context.fill(CGRect(x: length * 0.24, y: -width / 2, width: length * 0.6, height: width * 0.3))
        band(0.84, 0.9, 0xC9CDD4)
        band(0.9, 1.0, 0xFF9EB0)

        let cone = CGMutablePath()
        cone.move(to: .zero)
        cone.addLine(to: CGPoint(x: length * 0.24, y: -width / 2))
        cone.addLine(to: CGPoint(x: length * 0.24, y: width / 2))
        cone.closeSubpath()
        context.setFillColor(rgb(0xF2CFA0))
        context.addPath(cone)
        context.fillPath()

        let lead = CGMutablePath()
        lead.move(to: .zero)
        lead.addLine(to: CGPoint(x: length * 0.08, y: -width * 0.17))
        lead.addLine(to: CGPoint(x: length * 0.08, y: width * 0.17))
        lead.closeSubpath()
        context.setFillColor(rgb(0x2B2B2E))
        context.addPath(lead)
        context.fillPath()
        context.restoreGState()
    }

    /// A colour that stands out on top of the stroke: a white-hot tint of it, or
    /// warm amber when the stroke is already near white.
    private static func highlight(for color: CGColor) -> CGColor {
        guard let rgb = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let c = rgb.components, c.count >= 3 else { return Self.rgb(0xFFB13D) }
        let luminance = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
        guard luminance < 0.8 else { return Self.rgb(0xFFB13D) }
        return CGColor(srgbRed: c[0] + (1 - c[0]) * 0.6, green: c[1] + (1 - c[1]) * 0.6,
                       blue: c[2] + (1 - c[2]) * 0.6, alpha: 1)
    }

    private static func rgb(_ hex: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// Path length from its flattened segments; close enough to size the comet trail.
    private static func approximateLength(of path: Path) -> CGFloat {
        var total: CGFloat = 0
        var current = CGPoint.zero
        path.forEach { element in
            switch element {
            case .move(let to):
                current = to
            case .line(let to), .quadCurve(let to, _), .curve(let to, _, _):
                total += hypot(to.x - current.x, to.y - current.y)
                current = to
            case .closeSubpath:
                break
            }
        }
        return total
    }
}
