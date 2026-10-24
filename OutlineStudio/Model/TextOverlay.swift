//
//  TextOverlay.swift
//  OutlineStudio
//

import CoreGraphics
import Foundation

/// A piece of text that draws itself along its glyph outlines on top of the video.
///
/// Geometry is stored relative to the video so the same overlay renders identically
/// in the on-screen preview and in the full-resolution export.
struct TextOverlay: Identifiable, Equatable {
    enum DrawStyle: String, CaseIterable, Identifiable {
        /// Glyphs are traced one after another, like handwriting.
        case sequential
        /// Every glyph is traced at the same time.
        case together

        var id: Self { self }

        var title: String {
            switch self {
            case .sequential: "One by one"
            case .together: "All at once"
            }
        }
    }

    var id = UUID()
    var text = "Hello"
    var fontName = OutlineFont.defaultFont.postScriptName

    /// Font size as a fraction of the video height.
    var relativeSize: CGFloat = 0.12
    /// Outline width as a fraction of the font size.
    var strokeWidthRatio = OutlineFont.defaultFont.kind.defaultStrokeWidthRatio
    var strokeColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    var fillEnabled = true
    var fillColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

    /// Centre of the text in unit coordinates, top-left origin.
    var position = CGPoint(x: 0.5, y: 0.5)

    /// Seconds into the video when tracing begins.
    var startTime: Double = 0
    /// Seconds it takes to trace the full outline.
    var drawDuration: Double = 2
    /// Seconds into the video when the text fades away; `nil` holds it to the end.
    var endTime: Double?

    var style = DrawStyle.sequential
    var easing = Easing.easeInOut
}
