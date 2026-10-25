//
//  GlyphOutline.swift
//  OutlineStudio
//

import CoreText
import UIKit

/// Vector paths of a string, one `CGPath` per glyph.
///
/// For outline fonts the paths are the letters' borders; for single-line fonts
/// they are the pen strokes.
///
/// Paths are built at `referenceSize` in a y-down coordinate space centred on the
/// origin, so the live preview and the exporter can scale and
/// position them with the same transform.
final class GlyphOutline {
    static let referenceSize: CGFloat = 100

    /// Glyph paths in reading order.
    let glyphs: [CGPath]
    /// For each glyph, the index of the character in the text it was drawn for.
    let glyphCharacters: [Int]
    /// For each glyph, the length of its stroke, so a pen can move at an even speed.
    let glyphLengths: [CGFloat]
    /// One box per non-empty line: the line's ink width by its ascender-to-descender height.
    let lineBoxes: [CGRect]
    /// For each line box, the index of the first character drawn on that line.
    let lineFirstCharacters: [Int]
    /// All glyphs in one path; tracing it draws the glyphs one after another.
    let combined: CGPath
    let bounds: CGRect

    private static let cache = NSCache<NSString, GlyphOutline>()

    static func make(text: String, fontName: String) -> GlyphOutline {
        let key = "\(fontName)|\(text)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let outline = StrokeFont.named(fontName).map { GlyphOutline(text: text, strokeFont: $0) }
            ?? GlyphOutline(text: text, fontName: fontName)
        cache.setObject(outline, forKey: key)
        return outline
    }

    private convenience init(text: String, fontName: String) {
        let font = CTFontCreateWithName(fontName as CFString, Self.referenceSize, nil)
        let ascent = CTFontGetAscent(font)
        let lineHeight = ascent + CTFontGetDescent(font) + CTFontGetLeading(font)
        let lines = text.components(separatedBy: .newlines)
        let blockTop = -lineHeight * CGFloat(lines.count) / 2

        let descent = CTFontGetDescent(font)
        var glyphs: [CGPath] = []
        var glyphCharacters: [Int] = []
        var lineBoxes: [CGRect] = []
        var lineFirstCharacters: [Int] = []
        var lineStart = 0
        for (index, line) in lines.enumerated() {
            let firstGlyph = glyphs.count
            defer { lineStart += line.count + 1 }
            // Core Text reports UTF-16 offsets; map them back to character indices
            let characterAtUTF16 = line.indices.flatMap { index in
                Array(repeating: line.distance(from: line.startIndex, to: index), count: line[index].utf16.count)
            }
            let attributed = NSAttributedString(string: line,
                                                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            let ctLine = CTLineCreateWithAttributedString(attributed)
            let lineWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
            let originX = -lineWidth / 2
            let baseline = blockTop + CGFloat(index) * lineHeight + ascent

            for run in CTLineGetGlyphRuns(ctLine) as! [CTRun] {
                // Runs can use a fallback font for characters the chosen font lacks
                let attributes = CTRunGetAttributes(run) as NSDictionary
                let runFont: CTFont = attributes[kCTFontAttributeName].map { $0 as! CTFont } ?? font

                let count = CTRunGetGlyphCount(run)
                var glyphIDs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                var stringIndices = [CFIndex](repeating: 0, count: count)
                CTRunGetGlyphs(run, CFRange(), &glyphIDs)
                CTRunGetPositions(run, CFRange(), &positions)
                CTRunGetStringIndices(run, CFRange(), &stringIndices)

                for i in 0..<count {
                    // Flip CoreText's y-up glyph space and move the glyph onto its baseline
                    var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                                      tx: originX + positions[i].x,
                                                      ty: baseline - positions[i].y)
                    guard let path = CTFontCreatePathForGlyph(runFont, glyphIDs[i], &transform),
                          !path.isEmpty else { continue }
                    glyphs.append(path)
                    let utf16 = stringIndices[i]
                    glyphCharacters.append(lineStart + (characterAtUTF16.indices.contains(utf16) ? characterAtUTF16[utf16] : 0))
                }
            }
            if let box = Self.lineBox(glyphs[firstGlyph...], top: baseline - ascent, bottom: baseline + descent) {
                lineBoxes.append(box)
                lineFirstCharacters.append(glyphCharacters[firstGlyph])
            }
        }

        self.init(glyphs: glyphs, glyphCharacters: glyphCharacters,
                  lineBoxes: lineBoxes, lineFirstCharacters: lineFirstCharacters)
    }

    /// Lays out a single-line font, scaled so capitals match a regular font's proportions.
    private convenience init(text: String, strokeFont: StrokeFont) {
        let scale = Self.referenceSize * 0.7 / strokeFont.capHeight
        let lineHeight = Self.referenceSize * 1.25
        let lines = text.components(separatedBy: .newlines)
        let blockTop = -lineHeight * CGFloat(lines.count) / 2

        var glyphs: [CGPath] = []
        var glyphCharacters: [Int] = []
        var lineBoxes: [CGRect] = []
        var lineFirstCharacters: [Int] = []
        var lineStart = 0
        for (index, line) in lines.enumerated() {
            let firstGlyph = glyphs.count
            defer { lineStart += line.count + 1 }
            let glyphsInLine = line.map { strokeFont.glyphs[$0] }
            let lineWidth = glyphsInLine.reduce(0) { $0 + ($1?.advance ?? strokeFont.defaultAdvance) } * scale
            var penX = -lineWidth / 2
            let baseline = blockTop + CGFloat(index) * lineHeight + Self.referenceSize * 0.95

            for (offset, glyph) in glyphsInLine.enumerated() {
                let advance = (glyph?.advance ?? strokeFont.defaultAdvance) * scale
                defer { penX += advance }
                guard let glyph, !glyph.path.isEmpty else { continue }
                // Font units are y-up from the baseline; flip into the y-down layout space
                var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: penX, ty: baseline)
                if let path = glyph.path.copy(using: &transform) {
                    glyphs.append(path)
                    glyphCharacters.append(lineStart + offset)
                }
            }
            // Capitals reach 0.7 of the reference size; leave room above and for descenders
            if let box = Self.lineBox(glyphs[firstGlyph...],
                                      top: baseline - Self.referenceSize * 0.95,
                                      bottom: baseline + Self.referenceSize * 0.3) {
                lineBoxes.append(box)
                lineFirstCharacters.append(glyphCharacters[firstGlyph])
            }
        }

        self.init(glyphs: glyphs, glyphCharacters: glyphCharacters,
                  lineBoxes: lineBoxes, lineFirstCharacters: lineFirstCharacters)
    }

    private static func lineBox(_ glyphs: ArraySlice<CGPath>, top: CGFloat, bottom: CGFloat) -> CGRect? {
        guard let ink = glyphs.map(\.boundingBoxOfPath).reduce(nil, { $0?.union($1) ?? $1 }) else { return nil }
        return CGRect(x: ink.minX, y: top, width: ink.width, height: bottom - top)
    }

    private init(glyphs: [CGPath], glyphCharacters: [Int], lineBoxes: [CGRect], lineFirstCharacters: [Int]) {
        let combined = CGMutablePath()
        glyphs.forEach { combined.addPath($0) }

        self.glyphs = glyphs
        self.glyphCharacters = glyphCharacters
        self.glyphLengths = glyphs.map(\.approximateLength)
        self.lineBoxes = lineBoxes
        self.lineFirstCharacters = lineFirstCharacters
        self.combined = combined
        self.bounds = combined.isEmpty ? .zero : combined.boundingBoxOfPath
    }
}
