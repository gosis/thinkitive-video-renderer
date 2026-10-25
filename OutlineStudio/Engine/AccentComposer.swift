//
//  AccentComposer.swift
//  OutlineStudio
//

import CoreGraphics
import Foundation

/// Builds accented letters (š, ī, ž, ā, ķ, ą, ő…) that a stroke font lacks from
/// its base letter plus pen-drawn marks.
///
/// The bundled single-line fonts only cover basic Latin, so without this any
/// Latvian, Lithuanian, Polish, Czech and similar text would skip those letters.
/// Each mark is drawn after its letter, the way it's written by hand.
enum AccentComposer {
    private enum Mark: UInt32 {
        case grave = 0x300, acute, circumflex, tilde, macron
        case breve = 0x306, dotAbove, diaeresis
        case ring = 0x30A, doubleAcute, caron
        case commaBelow = 0x326, cedilla, ogonek

        var isBelow: Bool { self == .commaBelow || self == .cedilla || self == .ogonek }
    }

    /// Letters from Latin-1 Supplement and Latin Extended-A/B, where the font has
    /// the base letter but not the accented one.
    static func addingAccentedLetters(to glyphs: [Character: StrokeFont.Glyph],
                                      capHeight: CGFloat) -> [Character: StrokeFont.Glyph] {
        var result = glyphs
        let xHeight = glyphs["x"]?.path.boundingBoxOfPath.maxY ?? capHeight * 0.6
        for value in UInt32(0xC0)...0x24F {
            guard let scalar = Unicode.Scalar(value) else { continue }
            let character = Character(scalar)
            guard glyphs[character] == nil else { continue }

            let parts = Array(String(character).decomposedStringWithCanonicalMapping.unicodeScalars)
            guard parts.count > 1,
                  let base = glyphs[Character(parts[0])], !base.path.isEmpty else { continue }
            let marks = parts.dropFirst().compactMap { Mark(rawValue: $0.value) }
            guard marks.count == parts.count - 1 else { continue }

            let path = compose(base.path, letter: Character(parts[0]), marks: marks, xHeight: xHeight, unit: capHeight * 0.1)
            result[character] = StrokeFont.Glyph(path: path, advance: base.advance)
        }
        return result
    }

    private static func compose(_ basePath: CGPath, letter: Character, marks: [Mark],
                                xHeight: CGFloat, unit m: CGFloat) -> CGPath {
        var subpaths = basePath.subpaths
        // i and j lose their dot (every stroke above the x-height) under a mark above, like ī
        if "ij".contains(letter), marks.contains(where: { !$0.isBelow }) {
            let body = subpaths.filter { $0.boundingBoxOfPath.minY < xHeight }
            if !body.isEmpty { subpaths = body }
        }
        let result = CGMutablePath()
        subpaths.forEach { result.addPath($0) }
        let box = result.boundingBoxOfPath
        let points = result.points

        var top = box.maxY + m
        for mark in marks {
            switch mark {
            case .commaBelow, .cedilla, .ogonek:
                // Latvian ģ has its comma turned and above the letter, clear of the descender
                if letter == "g" {
                    add(turnedComma(m), to: result, at: CGPoint(x: centerX(of: points, above: box.maxY - box.height * 0.3), y: top))
                    top += 2 * m
                    continue
                }
                let feet = points.filter { $0.y <= box.minY + box.height * 0.3 && $0.y >= -m }
                let feetX = feet.isEmpty ? box.midX : (feet.map(\.x).min()! + feet.map(\.x).max()!) / 2
                switch mark {
                case .ogonek:
                    add(ogonek(m), to: result, at: CGPoint(x: (feet.map(\.x).max() ?? box.maxX) - m * 0.5, y: 0))
                case .cedilla where "CcSsTt".contains(letter):
                    add(cedilla(m), to: result, at: CGPoint(x: feetX, y: 0))
                default:
                    add(commaBelow(m), to: result, at: CGPoint(x: feetX, y: -m * 0.6))
                }
            default:
                let x = centerX(of: points, above: box.maxY - box.height * 0.35)
                add(shape(of: mark, m), to: result, at: CGPoint(x: x, y: top))
                top += 2.2 * m
            }
        }
        return result
    }

    /// The middle of the letter's ink at or above `y`, so slanted and joined-up
    /// letters get their mark over the body rather than over the lead-in stroke.
    private static func centerX(of points: [CGPoint], above y: CGFloat) -> CGFloat {
        let xs = points.filter { $0.y >= y }.map(\.x)
        guard let low = xs.min(), let high = xs.max() else { return 0 }
        return (low + high) / 2
    }

    private static func add(_ mark: CGPath, to path: CGMutablePath, at origin: CGPoint) {
        path.addPath(mark, transform: CGAffineTransform(translationX: origin.x, y: origin.y))
    }

    // MARK: Marks, in font units (y-up) around their attachment point

    private static func shape(of mark: Mark, _ m: CGFloat) -> CGPath {
        let path = CGMutablePath()
        switch mark {
        case .acute:
            path.addLines(between: [CGPoint(x: -0.6 * m, y: 0), CGPoint(x: 0.8 * m, y: 1.8 * m)])
        case .grave:
            path.addLines(between: [CGPoint(x: -0.8 * m, y: 1.8 * m), CGPoint(x: 0.6 * m, y: 0)])
        case .doubleAcute:
            for offset in [-0.7 * m, 0.7 * m] {
                path.addLines(between: [CGPoint(x: offset - 0.5 * m, y: 0), CGPoint(x: offset + 0.6 * m, y: 1.8 * m)])
            }
        case .circumflex:
            path.addLines(between: [CGPoint(x: -1.1 * m, y: 0), CGPoint(x: 0, y: 1.3 * m), CGPoint(x: 1.1 * m, y: 0)])
        case .caron:
            path.addLines(between: [CGPoint(x: -1.1 * m, y: 1.3 * m), CGPoint(x: 0, y: 0), CGPoint(x: 1.1 * m, y: 1.3 * m)])
        case .macron:
            path.addLines(between: [CGPoint(x: -1.3 * m, y: 0.5 * m), CGPoint(x: 1.3 * m, y: 0.5 * m)])
        case .breve:
            path.move(to: CGPoint(x: -1.1 * m, y: 1.3 * m))
            path.addQuadCurve(to: CGPoint(x: 1.1 * m, y: 1.3 * m), control: CGPoint(x: 0, y: -0.9 * m))
        case .tilde:
            path.move(to: CGPoint(x: -1.3 * m, y: 0.3 * m))
            path.addCurve(to: CGPoint(x: 1.3 * m, y: 0.9 * m),
                          control1: CGPoint(x: -0.5 * m, y: 1.7 * m), control2: CGPoint(x: 0.5 * m, y: -0.5 * m))
        case .dotAbove:
            addDot(at: CGPoint(x: 0, y: 0.5 * m), to: path, m)
        case .diaeresis:
            addDot(at: CGPoint(x: -0.8 * m, y: 0.5 * m), to: path, m)
            addDot(at: CGPoint(x: 0.8 * m, y: 0.5 * m), to: path, m)
        case .ring:
            path.addEllipse(in: CGRect(x: -0.65 * m, y: 0, width: 1.3 * m, height: 1.3 * m))
        case .commaBelow, .cedilla, .ogonek:
            break
        }
        return path
    }

    /// A tiny loop, which the line width rounds into a dot.
    private static func addDot(at center: CGPoint, to path: CGMutablePath, _ m: CGFloat) {
        path.addEllipse(in: CGRect(x: center.x - 0.2 * m, y: center.y - 0.2 * m, width: 0.4 * m, height: 0.4 * m))
    }

    private static func commaBelow(_ m: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0.2 * m, y: 0))
        path.addQuadCurve(to: CGPoint(x: -0.5 * m, y: -1.5 * m), control: CGPoint(x: 0.2 * m, y: -1 * m))
        return path
    }

    private static func turnedComma(_ m: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0.4 * m, y: 1.7 * m))
        path.addQuadCurve(to: CGPoint(x: -0.1 * m, y: 0.2 * m), control: CGPoint(x: -0.2 * m, y: 1.1 * m))
        return path
    }

    private static func cedilla(_ m: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: -0.2 * m, y: -0.6 * m))
        path.addCurve(to: CGPoint(x: -0.7 * m, y: -1.5 * m),
                      control1: CGPoint(x: 0.8 * m, y: -0.6 * m), control2: CGPoint(x: 0.8 * m, y: -1.6 * m))
        return path
    }

    private static func ogonek(_ m: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addCurve(to: CGPoint(x: 0.6 * m, y: -1.4 * m),
                      control1: CGPoint(x: -0.9 * m, y: -0.5 * m), control2: CGPoint(x: -0.6 * m, y: -1.5 * m))
        return path
    }
}

private extension CGPath {
    /// Each pen-down run as its own path.
    var subpaths: [CGPath] {
        var result: [CGMutablePath] = []
        applyWithBlock { pointer in
            let element = pointer.pointee
            let p = element.points
            switch element.type {
            case .moveToPoint:
                let path = CGMutablePath()
                path.move(to: p[0])
                result.append(path)
            case .addLineToPoint: result.last?.addLine(to: p[0])
            case .addQuadCurveToPoint: result.last?.addQuadCurve(to: p[1], control: p[0])
            case .addCurveToPoint: result.last?.addCurve(to: p[2], control1: p[0], control2: p[1])
            case .closeSubpath: result.last?.closeSubpath()
            @unknown default: break
            }
        }
        return result.filter { !$0.isEmpty }
    }

    /// Every on-curve and control point.
    var points: [CGPoint] {
        var result: [CGPoint] = []
        applyWithBlock { pointer in
            let element = pointer.pointee
            let count = switch element.type {
            case .moveToPoint, .addLineToPoint: 1
            case .addQuadCurveToPoint: 2
            case .addCurveToPoint: 3
            default: 0
            }
            for index in 0..<count { result.append(element.points[index]) }
        }
        return result
    }
}
