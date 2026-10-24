//
//  OutlineTiming.swift
//  OutlineStudio
//

import CoreGraphics

enum Easing: String, CaseIterable, Identifiable {
    case linear, easeInOut, easeOut

    var id: Self { self }

    var title: String {
        switch self {
        case .linear: "Linear"
        case .easeInOut: "Smooth"
        case .easeOut: "Ease out"
        }
    }

    private var controlPoints: (x1: Double, y1: Double, x2: Double, y2: Double) {
        switch self {
        case .linear: (0, 0, 1, 1)
        case .easeInOut: (0.42, 0, 0.58, 1)
        case .easeOut: (0, 0, 0.58, 1)
        }
    }

    /// Evaluates the cubic Bézier timing curve, matching the CSS / Core Animation presets.
    func apply(_ x: Double) -> Double {
        guard self != .linear else { return x }
        let c = controlPoints

        func bezier(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
        }

        // x(t) is monotonic for these curves, so bisection finds t quickly
        var low = 0.0, high = 1.0, t = x
        for _ in 0..<24 {
            t = (low + high) / 2
            if bezier(t, c.x1, c.x2) < x { low = t } else { high = t }
        }
        return bezier(t, c.y1, c.y2)
    }
}

extension TextOverlay {
    static let fadeOutDuration = 0.25

    /// The fill fades in once the outline is complete.
    var fillFadeDuration: Double {
        min(0.6, max(0.15, drawDuration * 0.35))
    }

    /// Fraction of the outline traced at `time`, eased.
    func strokeProgress(at time: Double) -> CGFloat {
        guard drawDuration > 0 else { return time >= startTime ? 1 : 0 }
        return CGFloat(easing.apply(clamp((time - startTime) / drawDuration)))
    }

    func fillOpacity(at time: Double) -> Double {
        guard drawsFill else { return 0 }
        return clamp((time - startTime - drawDuration) / fillFadeDuration)
    }

    /// Overall opacity, which drops to zero after `endTime`.
    func opacity(at time: Double) -> Double {
        guard let endTime else { return 1 }
        return 1 - clamp((time - endTime) / Self.fadeOutDuration)
    }
}

private func clamp(_ value: Double) -> Double {
    min(max(value, 0), 1)
}
