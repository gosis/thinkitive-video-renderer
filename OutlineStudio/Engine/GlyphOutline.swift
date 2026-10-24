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

        var glyphs: [CGPath] = []
        for (index, line) in lines.enumerated() {
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
                CTRunGetGlyphs(run, CFRange(), &glyphIDs)
                CTRunGetPositions(run, CFRange(), &positions)

                for i in 0..<count {
                    // Flip CoreText's y-up glyph space and move the glyph onto its baseline
                    var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                                      tx: originX + positions[i].x,
                                                      ty: baseline - positions[i].y)
                    guard let path = CTFontCreatePathForGlyph(runFont, glyphIDs[i], &transform),
                          !path.isEmpty else { continue }
                    glyphs.append(path)
                }
            }
        }

        self.init(glyphs: glyphs)
    }

    /// Lays out a single-line font, scaled so capitals match a regular font's proportions.
    private convenience init(text: String, strokeFont: StrokeFont) {
        let scale = Self.referenceSize * 0.7 / strokeFont.capHeight
        let lineHeight = Self.referenceSize * 1.25
        let lines = text.components(separatedBy: .newlines)
        let blockTop = -lineHeight * CGFloat(lines.count) / 2

        var glyphs: [CGPath] = []
        for (index, line) in lines.enumerated() {
            let glyphsInLine = line.map { strokeFont.glyphs[$0] }
            let lineWidth = glyphsInLine.reduce(0) { $0 + ($1?.advance ?? strokeFont.defaultAdvance) } * scale
            var penX = -lineWidth / 2
            let baseline = blockTop + CGFloat(index) * lineHeight + Self.referenceSize * 0.95

            for glyph in glyphsInLine {
                let advance = (glyph?.advance ?? strokeFont.defaultAdvance) * scale
                defer { penX += advance }
                guard let glyph, !glyph.path.isEmpty else { continue }
                // Font units are y-up from the baseline; flip into the y-down layout space
                var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: penX, ty: baseline)
                if let path = glyph.path.copy(using: &transform) {
                    glyphs.append(path)
                }
            }
        }

        self.init(glyphs: glyphs)
    }

    private init(glyphs: [CGPath]) {
        let combined = CGMutablePath()
        glyphs.forEach { combined.addPath($0) }

        self.glyphs = glyphs
        self.combined = combined
        self.bounds = combined.isEmpty ? .zero : combined.boundingBoxOfPath
    }
}
