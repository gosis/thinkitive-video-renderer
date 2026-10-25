//
//  InkcapMark.swift
//  OutlineStudio
//

import SwiftUI

/// The app icon's mark: one pen stroke that loops and ends in a glowing pen tip.
/// Drawn from the same curve as the icon, in a unit square.
struct InkcapMark: View {
    var color: Color = Theme.accent

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            // The icon's stroke sits in x 0.13…0.84, y 0.26…0.75; frame it to fill the view
            let transform = CGAffineTransform(translationX: (size.width - side) / 2, y: (size.height - side) / 2)
                .scaledBy(x: side / 0.74, y: side / 0.74)
                .translatedBy(x: -0.12, y: -0.13)
            let points = Self.samples.map { $0.applying(transform) }

            // Tapered: thin where the pen started, thick at the tip
            for index in 1..<points.count {
                let t = CGFloat(index) / CGFloat(points.count - 1)
                var segment = Path()
                segment.move(to: points[index - 1])
                segment.addLine(to: points[index])
                context.stroke(segment, with: .color(color),
                               style: StrokeStyle(lineWidth: side * (0.047 + 0.075 * t), lineCap: .round))
            }
            if let tip = points.last {
                let radius = side * 0.07
                context.fill(Path(ellipseIn: CGRect(x: tip.x - radius, y: tip.y - radius,
                                                    width: radius * 2, height: radius * 2)),
                             with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }

    /// The icon's loop (y flipped to top-left origin), sampled along its three curves.
    private static let samples: [CGPoint] = {
        let curves: [(CGPoint, CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: 0.17, y: 0.64), CGPoint(x: 0.30, y: 0.62), CGPoint(x: 0.50, y: 0.45), CGPoint(x: 0.47, y: 0.30)),
            (CGPoint(x: 0.47, y: 0.30), CGPoint(x: 0.44, y: 0.16), CGPoint(x: 0.26, y: 0.40), CGPoint(x: 0.45, y: 0.64)),
            (CGPoint(x: 0.45, y: 0.64), CGPoint(x: 0.56, y: 0.74), CGPoint(x: 0.66, y: 0.66), CGPoint(x: 0.74, y: 0.56)),
        ]
        var points: [CGPoint] = [curves[0].0]
        for (a, b, c, d) in curves {
            for step in 1...24 {
                let t = CGFloat(step) / 24, u = 1 - t
                let w0 = u * u * u, w1 = 3 * u * u * t, w2 = 3 * u * t * t, w3 = t * t * t
                points.append(CGPoint(x: w0 * a.x + w1 * b.x + w2 * c.x + w3 * d.x,
                                      y: w0 * a.y + w1 * b.y + w2 * c.y + w3 * d.y))
            }
        }
        return points
    }()
}
