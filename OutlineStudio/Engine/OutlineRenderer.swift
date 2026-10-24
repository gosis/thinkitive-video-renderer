//
//  OutlineRenderer.swift
//  OutlineStudio
//

import CoreGraphics
import SwiftUI

/// Draws an overlay's state at a point in time into a y-down `CGContext`.
///
/// The live preview (through `GraphicsContext.withCGContext`) and the exporter
/// (one bitmap per video frame) both draw through here, so what you see while
/// editing is exactly what gets rendered.
enum OutlineRenderer {
    static func draw(_ overlay: TextOverlay, at time: Double, in context: CGContext, videoSize: CGSize) {
        let opacity = overlay.opacity(at: time)
        let progress = overlay.strokeProgress(at: time)
        guard opacity > 0, progress > 0 else { return }

        let transform = overlay.transform(in: videoSize)

        let fillOpacity = overlay.fillOpacity(at: time)
        if fillOpacity > 0 {
            context.saveGState()
            context.setAlpha(opacity * fillOpacity)
            context.addPath(Path(overlay.outline.combined).applying(transform).cgPath)
            context.setFillColor(overlay.fillColor)
            context.fillPath()
            context.restoreGState()
        }

        context.saveGState()
        context.setAlpha(opacity)
        context.setStrokeColor(overlay.strokeColor)
        context.setLineWidth(overlay.strokeWidth(in: videoSize))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for path in overlay.strokePaths {
            // SwiftUI's Path provides length-based trimming, which Core Graphics lacks
            context.addPath(Path(path).applying(transform).trimmedPath(from: 0, to: progress).cgPath)
            context.strokePath()
        }
        context.restoreGState()
    }

    /// Whether anything of the overlay is visible at `time`.
    static func isVisible(_ overlay: TextOverlay, at time: Double) -> Bool {
        overlay.opacity(at: time) > 0 && overlay.strokeProgress(at: time) > 0
    }
}
