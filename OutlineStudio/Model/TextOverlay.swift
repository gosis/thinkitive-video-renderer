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
    /// A dark edge that keeps light text readable over bright footage.
    var shadowEnabled = false
    /// A rounded box behind each line of text.
    var backgroundEnabled = false
    var backgroundColor = CGColor(gray: 0, alpha: 0.6)

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
    /// A marker on the point being drawn; off by default.
    var pointer = PenPointer.off

    /// When set, each word is written while it's spoken instead of the whole text
    /// being traced over `drawDuration`. Used by auto captions.
    var wordTimings: [WordTiming]?
    /// How word-timed text is written.
    var writingPace = WritingPace.smooth
    /// Word-timed text is completely written by this time, so the last words of a
    /// video finish before it ends.
    var writeBy: Double?
}

/// How text with word timings is written.
enum WritingPace: String, CaseIterable, Identifiable {
    /// Each word is written in the moment it's spoken.
    case synced
    /// The pen moves steadily through the whole caption, never ahead of the
    /// speech and never far behind it.
    case smooth

    var id: Self { self }

    var title: String {
        switch self {
        case .synced: "Synced to speech"
        case .smooth: "Smooth pen"
        }
    }
}

/// The span of `TextOverlay.text` (in characters) that is written between two times.
struct WordTiming: Equatable {
    var characters: Range<Int>
    var start: Double
    var end: Double
}
