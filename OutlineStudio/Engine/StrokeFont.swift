//
//  StrokeFont.swift
//  OutlineStudio
//

import CoreGraphics
import Foundation

/// A single-line ("stroke" or "engraving") font loaded from an SVG font file.
///
/// Unlike regular fonts, which describe the border of each letter, these store
/// the centre line a pen would follow, so tracing them draws each letter with
/// one line, the way handwriting animations in editing apps do.
final class StrokeFont {
    struct Glyph {
        /// Pen path in font units, y-up from the baseline.
        let path: CGPath
        let advance: CGFloat
    }

    let glyphs: [Character: Glyph]
    let defaultAdvance: CGFloat
    /// Height of a capital letter in font units, measured from the glyphs.
    let capHeight: CGFloat

    /// A font bundled in the app, by resource name. Each font is parsed the first
    /// time it's asked for; this is safe to call from the export thread.
    static func named(_ resource: String) -> StrokeFont? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = loaded[resource] {
            return cached
        }
        guard OutlineFont.named(resource)?.kind == .singleLine,
              let url = Bundle.main.url(forResource: resource, withExtension: "svg") else { return nil }
        let font = StrokeFont(contentsOf: url)
        loaded[resource] = font
        return font
    }

    private static let lock = NSLock()
    private static var loaded: [String: StrokeFont?] = [:]

    private init?(contentsOf url: URL) {
        guard let parser = XMLParser(contentsOf: url) else { return nil }
        let reader = SVGFontReader()
        parser.delegate = reader
        guard parser.parse(), !reader.glyphs.isEmpty else { return nil }

        glyphs = reader.glyphs
        defaultAdvance = reader.defaultAdvance
        let measured = ["H", "E", "I"].compactMap { reader.glyphs[$0]?.path.boundingBoxOfPath.maxY }.max()
        capHeight = measured ?? reader.unitsPerEm * 0.7
    }
}

// MARK: - SVG font parsing

private final class SVGFontReader: NSObject, XMLParserDelegate {
    var glyphs: [Character: StrokeFont.Glyph] = [:]
    var defaultAdvance: CGFloat = 500
    var unitsPerEm: CGFloat = 1000

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        switch element {
        case "font":
            if let advance = attributes["horiz-adv-x"].flatMap(Double.init) {
                defaultAdvance = CGFloat(advance)
            }
        case "font-face":
            if let units = attributes["units-per-em"].flatMap(Double.init) {
                unitsPerEm = CGFloat(units)
            }
        case "glyph":
            // Single characters only; ligature glyphs are skipped
            guard let unicode = attributes["unicode"], unicode.count == 1, let character = unicode.first else { return }
            let advance = attributes["horiz-adv-x"].flatMap(Double.init).map { CGFloat($0) } ?? defaultAdvance
            let path = attributes["d"].map {
                PolylineSmoother.smooth(SVGPathParser.parse($0), unit: unitsPerEm)
            } ?? CGMutablePath()
            glyphs[character] = StrokeFont.Glyph(path: path, advance: advance)
        default:
            break
        }
    }
}

/// Turns runs of straight segments into smooth curves.
///
/// The Hershey fonts date from 1960s plotters and store every curve as a short
/// polyline snapped to a coarse grid, which looks faceted at video sizes. Each
/// straight run is relaxed to remove the grid jitter, then drawn as a quadratic
/// B-spline. Cusps, where the pen nearly
/// reverses, and joins between two long straight strokes are kept as corners, so
/// letters like "v" or "H" stay crisp while loops and bowls become round.
enum PolylineSmoother {
    /// Turns sharper than this (in radians) are always corners.
    private static let cuspAngle: CGFloat = 115 * .pi / 180
    /// Turns sharper than this are corners when both neighbouring segments are long.
    private static let strokeCornerAngle: CGFloat = 50 * .pi / 180

    /// - Parameter unit: The font's units per em; smoothing distances scale with it.
    static func smooth(_ path: CGPath, unit: CGFloat) -> CGPath {
        let longSegment = unit * 0.15
        let result = CGMutablePath()
        var run: [CGPoint] = []

        func flush() {
            appendSmoothed(run, to: result, longSegment: longSegment, unit: unit)
            run.removeAll()
        }

        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint:
                flush()
                run = [e.points[0]]
            case .addLineToPoint:
                run.append(e.points[0])
            case .addCurveToPoint:
                let start = run.last ?? e.points[2]
                if e.points[0] == start && e.points[1] == e.points[2] {
                    // A cubic with its controls on its ends is just a line
                    run.append(e.points[2])
                } else {
                    flush()
                    result.addCurve(to: e.points[2], control1: e.points[0], control2: e.points[1])
                    run = [e.points[2]]
                }
            case .addQuadCurveToPoint:
                flush()
                result.addQuadCurve(to: e.points[1], control: e.points[0])
                run = [e.points[1]]
            case .closeSubpath:
                if let first = run.first { run.append(first) }
                flush()
            @unknown default:
                break
            }
        }
        flush()
        return result
    }

    /// Appends one polyline, starting a new subpath unless it continues the current point.
    private static func appendSmoothed(_ points: [CGPoint], to path: CGMutablePath, longSegment: CGFloat, unit: CGFloat) {
        let points = points.enumerated().filter { $0.offset == 0 || $0.element != points[$0.offset - 1] }.map(\.element)
        guard let first = points.first else { return }
        if path.isEmpty || path.currentPoint != first {
            path.move(to: first)
        }
        guard points.count > 1 else { return }

        let closed = points.count > 3 && points.first == points.last
        let count = points.count

        func isCorner(_ i: Int) -> Bool {
            let hasNeighbours = closed || (i > 0 && i < count - 1)
            guard hasNeighbours else { return true }
            let previous = points[i == 0 ? count - 2 : i - 1]
            let next = points[i == count - 1 ? 1 : i + 1]
            let incoming = atan2(points[i].y - previous.y, points[i].x - previous.x)
            let outgoing = atan2(next.y - points[i].y, next.x - points[i].x)
            var turn = abs(outgoing - incoming)
            if turn > .pi { turn = 2 * .pi - turn }
            if turn > cuspAngle { return true }
            let shortest = min(hypot(points[i].x - previous.x, points[i].y - previous.y),
                               hypot(next.x - points[i].x, next.y - points[i].y))
            return turn > strokeCornerAngle && shortest > longSegment
        }

        let corners = (0..<count).filter(isCorner)

        // A closed loop with no corners (an "o", a dot) is one continuous curve
        if closed && corners.isEmpty {
            let loop = Array(points.dropLast())
            // Dots are too small to relax; the curve alone rounds them
            let size = boundingBox(of: loop).size
            let ring = max(size.width, size.height) < unit * 0.15 ? loop : relaxed(loop, closed: true, unit: unit)
            let mid = { (i: Int) in midpoint(ring[i % ring.count], ring[(i + 1) % ring.count]) }
            // Start on the curve itself so the seam doesn't leave a tick at the first point
            path.move(to: mid(0))
            for i in 1...ring.count {
                path.addQuadCurve(to: mid(i), control: ring[i % ring.count])
            }
            return
        }

        // Otherwise smooth each stretch between corners separately; corners stay put
        let breaks = Array(Set([0, count - 1] + corners)).sorted()
        for (a, b) in zip(breaks, breaks.dropFirst()) {
            let stretch = b - a > 1 ? relaxed(Array(points[a...b]), closed: false, unit: unit) : [points[a], points[b]]
            appendBSpline(stretch, to: path)
        }
    }

    /// Quadratic B-spline from the first to the last point: passes near the inner
    /// points rather than through them.
    private static func appendBSpline(_ points: [CGPoint], to path: CGMutablePath) {
        guard points.count > 2 else {
            if let last = points.last { path.addLine(to: last) }
            return
        }
        path.addLine(to: midpoint(points[0], points[1]))
        for i in 1..<(points.count - 1) {
            let end = i + 2 == points.count ? points[i + 1] : midpoint(points[i], points[i + 1])
            path.addQuadCurve(to: end, control: points[i])
        }
    }

    /// Evens out the jitter of grid-snapped plotter coordinates.
    ///
    /// The stretch is resampled at an even spacing, then repeated neighbour
    /// averaging acts like a Gaussian blur over roughly one grid cell. That removes
    /// the snapping while barely changing the letter (curves shrink by ~2%).
    /// Open stretches keep their end points fixed, so letters still join up.
    private static func relaxed(_ points: [CGPoint], closed: Bool, unit: CGFloat) -> [CGPoint] {
        let spacing = unit * 0.006
        let blurRadius = unit * 0.06
        var dense = resampled(points, closed: closed, spacing: spacing)
        let n = dense.count
        guard n > 2 else { return dense }

        // Each pass spreads a point over its neighbours; enough passes give the blur radius
        let passes = Int((blurRadius * blurRadius) / (0.5 * spacing * spacing))
        for _ in 0..<passes {
            let current = dense
            for i in 0..<n {
                if !closed && (i == 0 || i == n - 1) { continue }
                let previous = current[(i - 1 + n) % n], next = current[(i + 1) % n]
                dense[i].x = (previous.x + 2 * current[i].x + next.x) / 4
                dense[i].y = (previous.y + 2 * current[i].y + next.y) / 4
            }
        }
        return dense
    }

    /// Points evenly spaced along the polyline, including its end points when open.
    private static func resampled(_ points: [CGPoint], closed: Bool, spacing: CGFloat) -> [CGPoint] {
        let corners = closed ? points + [points[0]] : points
        var result: [CGPoint] = [corners[0]]
        var carried: CGFloat = 0
        for (a, b) in zip(corners, corners.dropFirst()) {
            let length = hypot(b.x - a.x, b.y - a.y)
            guard length > 0 else { continue }
            var distance = spacing - carried
            while distance < length {
                let t = distance / length
                result.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                distance += spacing
            }
            carried = length - (distance - spacing)
        }
        if closed {
            // The loop wraps back to the first point on its own
            if let last = result.last, hypot(last.x - corners[0].x, last.y - corners[0].y) < spacing / 2 {
                result.removeLast()
            }
        } else if let last = corners.last, result.last != last {
            result.append(last)
        }
        return result
    }

    private static func boundingBox(of points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .null }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}

/// Parses SVG path data (`M L H V C S Q T Z`, absolute and relative) into a `CGPath`.
enum SVGPathParser {
    static func parse(_ data: String) -> CGPath {
        let path = CGMutablePath()
        var scanner = Tokenizer(data)
        var command: Character = "M"
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastControl: CGPoint?
        var lastCommand: Character = "M"

        while let next = scanner.nextCommandOrNumber() {
            if case .command(let letter) = next {
                command = letter
                if letter == "Z" || letter == "z" {
                    path.closeSubpath()
                    current = subpathStart
                    lastControl = nil
                    lastCommand = letter
                    continue
                }
            } else {
                scanner.pushBack(next)
            }

            let relative = command.isLowercase
            func point() -> CGPoint? {
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }

            switch command.uppercased().first! {
            case "M":
                guard let p = point() else { return path }
                path.move(to: p)
                current = p
                subpathStart = p
                lastControl = nil
                // Further coordinate pairs after a move are implicit line-tos
                command = relative ? "l" : "L"
            case "L":
                guard let p = point() else { return path }
                path.addLine(to: p)
                current = p
                lastControl = nil
            case "H":
                guard let x = scanner.number() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                lastControl = nil
            case "V":
                guard let y = scanner.number() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                lastControl = nil
            case "C":
                guard let c1 = point(), let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p
                lastControl = c2
            case "S":
                let c1 = reflectedControl(lastControl, current, smoothAfter: "CS", lastCommand)
                guard let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p
                lastControl = c2
            case "Q":
                guard let c = point(), let p = point() else { return path }
                path.addQuadCurve(to: p, control: c)
                current = p
                lastControl = c
            case "T":
                let c = reflectedControl(lastControl, current, smoothAfter: "QT", lastCommand)
                guard let p = point() else { return path }
                path.addQuadCurve(to: p, control: c)
                current = p
                lastControl = c
            default:
                // Unsupported command (e.g. arcs): skip its numbers
                _ = scanner.number()
            }
            lastCommand = command
        }
        return path
    }

    private static func reflectedControl(_ control: CGPoint?, _ current: CGPoint,
                                         smoothAfter previous: String, _ lastCommand: Character) -> CGPoint {
        guard let control, previous.contains(lastCommand.uppercased()) else { return current }
        return CGPoint(x: 2 * current.x - control.x, y: 2 * current.y - control.y)
    }

    private struct Tokenizer {
        enum Token { case command(Character), number(CGFloat) }

        private let characters: [Character]
        private var index = 0
        private var pending: Token?

        init(_ string: String) { characters = Array(string) }

        mutating func pushBack(_ token: Token) { pending = token }

        mutating func nextCommandOrNumber() -> Token? {
            if let pending { self.pending = nil; return pending }
            skipSeparators()
            guard index < characters.count else { return nil }
            let character = characters[index]
            if character.isLetter && character != "e" && character != "E" {
                index += 1
                return .command(character)
            }
            return readNumber().map { .number($0) }
        }

        mutating func number() -> CGFloat? {
            if case .number(let value)? = pending { pending = nil; return value }
            guard pending == nil else { return nil }
            skipSeparators()
            return readNumber()
        }

        private mutating func skipSeparators() {
            while index < characters.count, characters[index].isWhitespace || characters[index] == "," {
                index += 1
            }
        }

        private mutating func readNumber() -> CGFloat? {
            let start = index
            var seenDot = false, seenExponent = false
            if index < characters.count, characters[index] == "-" || characters[index] == "+" { index += 1 }
            while index < characters.count {
                let c = characters[index]
                if c.isNumber {
                    index += 1
                } else if c == ".", !seenDot, !seenExponent {
                    seenDot = true
                    index += 1
                } else if c == "e" || c == "E", !seenExponent {
                    seenExponent = true
                    index += 1
                    if index < characters.count, characters[index] == "-" || characters[index] == "+" { index += 1 }
                } else {
                    break
                }
            }
            guard index > start, let value = Double(String(characters[start..<index])) else {
                index = max(index, start + 1)
                return nil
            }
            return CGFloat(value)
        }
    }
}
