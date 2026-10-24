//
//  OutlineGeometry.swift
//  OutlineStudio
//

import CoreGraphics

/// Maps an overlay's relative geometry onto a concrete video size.
///
/// The preview passes the on-screen video size in points, the exporter passes the
/// render size in pixels; both get the same layout.
extension TextOverlay {
    var outline: GlyphOutline {
        GlyphOutline.make(text: text, fontName: fontName)
    }

    var font: OutlineFont {
        OutlineFont.named(fontName) ?? .defaultFont
    }

    /// Single-line strokes have no inside to fill.
    var drawsFill: Bool {
        fillEnabled && font.kind == .outline
    }

    /// Paths to trace: one combined path for sequential drawing, or one per glyph.
    var strokePaths: [CGPath] {
        style == .sequential ? [outline.combined] : outline.glyphs
    }

    func fontSize(in videoSize: CGSize) -> CGFloat {
        relativeSize * videoSize.height
    }

    func strokeWidth(in videoSize: CGSize) -> CGFloat {
        strokeWidthRatio * fontSize(in: videoSize)
    }

    /// Transform from `GlyphOutline` space into video space.
    func transform(in videoSize: CGSize) -> CGAffineTransform {
        let scale = fontSize(in: videoSize) / GlyphOutline.referenceSize
        return CGAffineTransform(translationX: position.x * videoSize.width,
                                 y: position.y * videoSize.height)
            .scaledBy(x: scale, y: scale)
    }

    /// Bounding box of the drawn text, including the outline width.
    func frame(in videoSize: CGSize) -> CGRect {
        let inset = -strokeWidth(in: videoSize)
        return outline.bounds
            .applying(transform(in: videoSize))
            .insetBy(dx: inset, dy: inset)
    }
}
