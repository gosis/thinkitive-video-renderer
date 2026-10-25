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
    enum DrawStyle: String, CaseIterable, Identifiable, Codable {
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
    /// The video's width ÷ height. When set, the text wraps to fit within the frame.
    /// Captions do their own layout and leave this unset.
    var wrapAspectRatio: CGFloat?
    /// How word-timed text is written.
    var writingPace = WritingPace.smooth
    /// Word-timed text is completely written by this time, so the last words of a
    /// video finish before it ends.
    var writeBy: Double?
}

/// How text with word timings is written.
enum WritingPace: String, CaseIterable, Identifiable, Codable {
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
struct WordTiming: Equatable, Codable {
    var characters: Range<Int>
    var start: Double
    var end: Double
}

// MARK: - Saving

/// Saved as plain values so projects survive app updates: colours as sRGB
/// components, and every field optional when reading so older saves still open.
extension TextOverlay: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, text, fontName, relativeSize, strokeWidthRatio, strokeColor, fillEnabled, fillColor
        case shadowEnabled, backgroundEnabled, backgroundColor, position, startTime, drawDuration, endTime
        case style, easing, pointer, wordTimings, wrapAspectRatio, writingPace, writeBy
    }

    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? id
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? text
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? fontName
        relativeSize = try c.decodeIfPresent(CGFloat.self, forKey: .relativeSize) ?? relativeSize
        strokeWidthRatio = try c.decodeIfPresent(CGFloat.self, forKey: .strokeWidthRatio) ?? strokeWidthRatio
        strokeColor = try c.decodeIfPresent(SavedColor.self, forKey: .strokeColor)?.cgColor ?? strokeColor
        fillEnabled = try c.decodeIfPresent(Bool.self, forKey: .fillEnabled) ?? fillEnabled
        fillColor = try c.decodeIfPresent(SavedColor.self, forKey: .fillColor)?.cgColor ?? fillColor
        shadowEnabled = try c.decodeIfPresent(Bool.self, forKey: .shadowEnabled) ?? shadowEnabled
        backgroundEnabled = try c.decodeIfPresent(Bool.self, forKey: .backgroundEnabled) ?? backgroundEnabled
        backgroundColor = try c.decodeIfPresent(SavedColor.self, forKey: .backgroundColor)?.cgColor ?? backgroundColor
        position = try c.decodeIfPresent(CGPoint.self, forKey: .position) ?? position
        startTime = try c.decodeIfPresent(Double.self, forKey: .startTime) ?? startTime
        drawDuration = try c.decodeIfPresent(Double.self, forKey: .drawDuration) ?? drawDuration
        endTime = try c.decodeIfPresent(Double.self, forKey: .endTime)
        style = try c.decodeIfPresent(DrawStyle.self, forKey: .style) ?? style
        easing = try c.decodeIfPresent(Easing.self, forKey: .easing) ?? easing
        pointer = try c.decodeIfPresent(PenPointer.self, forKey: .pointer) ?? pointer
        wordTimings = try c.decodeIfPresent([WordTiming].self, forKey: .wordTimings)
        wrapAspectRatio = try c.decodeIfPresent(CGFloat.self, forKey: .wrapAspectRatio)
        writingPace = try c.decodeIfPresent(WritingPace.self, forKey: .writingPace) ?? writingPace
        writeBy = try c.decodeIfPresent(Double.self, forKey: .writeBy)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(fontName, forKey: .fontName)
        try c.encode(relativeSize, forKey: .relativeSize)
        try c.encode(strokeWidthRatio, forKey: .strokeWidthRatio)
        try c.encode(SavedColor(strokeColor), forKey: .strokeColor)
        try c.encode(fillEnabled, forKey: .fillEnabled)
        try c.encode(SavedColor(fillColor), forKey: .fillColor)
        try c.encode(shadowEnabled, forKey: .shadowEnabled)
        try c.encode(backgroundEnabled, forKey: .backgroundEnabled)
        try c.encode(SavedColor(backgroundColor), forKey: .backgroundColor)
        try c.encode(position, forKey: .position)
        try c.encode(startTime, forKey: .startTime)
        try c.encode(drawDuration, forKey: .drawDuration)
        try c.encodeIfPresent(endTime, forKey: .endTime)
        try c.encode(style, forKey: .style)
        try c.encode(easing, forKey: .easing)
        try c.encode(pointer, forKey: .pointer)
        try c.encodeIfPresent(wordTimings, forKey: .wordTimings)
        try c.encodeIfPresent(wrapAspectRatio, forKey: .wrapAspectRatio)
        try c.encode(writingPace, forKey: .writingPace)
        try c.encodeIfPresent(writeBy, forKey: .writeBy)
    }
}

/// A colour as sRGB components.
private struct SavedColor: Codable {
    var red, green, blue, alpha: CGFloat

    init(_ color: CGColor) {
        let srgb = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)
        let c = srgb?.components ?? [1, 1, 1, 1]
        red = c[0]
        green = c.count > 2 ? c[1] : c[0]
        blue = c.count > 2 ? c[2] : c[0]
        alpha = c.last ?? 1
    }

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
