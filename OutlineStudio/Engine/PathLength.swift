//
//  PathLength.swift
//  OutlineStudio
//

import CoreGraphics

extension CGPath {
    /// Length along the path, with curves flattened into short segments.
    var approximateLength: CGFloat {
        var total: CGFloat = 0
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero

        func walk(_ point: (CGFloat) -> CGPoint) {
            var last = current
            for step in 1...12 {
                let next = point(CGFloat(step) / 12)
                total += hypot(next.x - last.x, next.y - last.y)
                last = next
            }
            current = last
        }

        applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                current = points[0]
                subpathStart = current
            case .addLineToPoint:
                total += hypot(points[0].x - current.x, points[0].y - current.y)
                current = points[0]
            case .addQuadCurveToPoint:
                let start = current, control = points[0], end = points[1]
                walk { t in quadPoint(start, control, end, t) }
            case .addCurveToPoint:
                let start = current, c1 = points[0], c2 = points[1], end = points[2]
                walk { t in cubicPoint(start, c1, c2, end, t) }
            case .closeSubpath:
                total += hypot(subpathStart.x - current.x, subpathStart.y - current.y)
                current = subpathStart
            @unknown default:
                break
            }
        }
        return total
    }
}

private func quadPoint(_ start: CGPoint, _ control: CGPoint, _ end: CGPoint, _ t: CGFloat) -> CGPoint {
    let u = 1 - t
    let a = u * u, b = 2 * u * t, c = t * t
    let x = a * start.x + b * control.x + c * end.x
    let y = a * start.y + b * control.y + c * end.y
    return CGPoint(x: x, y: y)
}

private func cubicPoint(_ start: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ end: CGPoint, _ t: CGFloat) -> CGPoint {
    let u = 1 - t
    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
    let x = a * start.x + b * c1.x + c * c2.x + d * end.x
    let y = a * start.y + b * c1.y + c * c2.y + d * end.y
    return CGPoint(x: x, y: y)
}
