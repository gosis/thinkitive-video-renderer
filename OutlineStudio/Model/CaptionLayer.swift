//
//  CaptionLayer.swift
//  OutlineStudio
//

import CoreGraphics
import Foundation

/// A spoken word and when it is said, in seconds into the video.
struct CaptionWord: Equatable, Codable {
    var text: String
    var start: Double
    var end: Double
}

/// One on-screen caption: a short phrase whose words write themselves as they're spoken.
struct Caption: Identifiable, Equatable, Codable {
    var id = UUID()
    var words: [CaptionWord]

    var text: String { words.map(\.text).joined(separator: " ") }
    var start: Double { words.first?.start ?? 0 }
    var end: Double { words.last?.end ?? 0 }

    /// Replaces the text, spreading the new words evenly over the same time span.
    mutating func setText(_ text: String) {
        let pieces = text.split(whereSeparator: \.isWhitespace).map(String.init)
        words = Self.spread(pieces, from: start, to: end)
    }

    /// Moves and stretches the caption, keeping each word's relative timing.
    mutating func retime(start newStart: Double, end newEnd: Double) {
        let oldStart = start, oldLength = max(end - start, 0.001)
        let newLength = max(newEnd - newStart, 0.1)
        words = words.map { word in
            CaptionWord(text: word.text,
                        start: newStart + (word.start - oldStart) / oldLength * newLength,
                        end: newStart + (word.end - oldStart) / oldLength * newLength)
        }
    }

    private static func spread(_ pieces: [String], from start: Double, to end: Double) -> [CaptionWord] {
        guard !pieces.isEmpty else { return [] }
        let step = max(end - start, 0.1) / Double(pieces.count)
        return pieces.enumerated().map { index, piece in
            CaptionWord(text: piece, start: start + Double(index) * step, end: start + Double(index + 1) * step)
        }
    }
}

/// Auto-generated captions sharing one style.
struct CaptionLayer: Equatable, Codable {
    /// Font, colour, size and position for every caption; its text and timing are unused.
    var style: TextOverlay
    var captions: [Caption]

    /// Captions stay up briefly after their last word.
    static let hold = 0.6
    private static let maxWords = 6
    private static let maxCharacters = 32
    private static let pauseBreak = 0.6
    /// A caption wraps onto two lines when one line would need shrinking below this share of the set size.
    private static let wrapBelowScale: CGFloat = 0.9

    init(words: [CaptionWord]) {
        var style = TextOverlay()
        style.text = ""
        style.fontName = "ReliefSingleLine"
        style.relativeSize = 0.1
        style.strokeWidthRatio = 0.08
        style.shadowEnabled = true
        style.position = CGPoint(x: 0.5, y: 0.82)
        style.easing = .linear
        self.style = style
        self.captions = Self.group(words)
    }

    /// Splits speech into readable phrases at pauses, sentence ends and length limits.
    static func group(_ words: [CaptionWord]) -> [Caption] {
        var captions: [Caption] = []
        var current: [CaptionWord] = []

        for word in words {
            if let last = current.last {
                let length = (current + [word]).map(\.text).joined(separator: " ").count
                let sentenceEnded = last.text.last.map { ".?!".contains($0) } ?? false
                if word.start - last.end > pauseBreak || sentenceEnded
                    || current.count >= maxWords || length > maxCharacters {
                    captions.append(Caption(words: current))
                    current = []
                }
            }
            current.append(word)
        }
        if !current.isEmpty {
            captions.append(Caption(words: current))
        }
        return captions
    }

    /// The overlay that draws `caption`, sized so it fits a video of `aspectRatio`
    /// (width / height) and written before the video ends at `videoDuration`.
    func overlay(for caption: Caption, aspectRatio: CGFloat, videoDuration: Double) -> TextOverlay {
        var overlay = style
        overlay.id = caption.id
        // Appear just ahead of the first word, but not until the previous caption has gone
        overlay.startTime = max(caption.start - OutlineRenderer.wordLead, previousGone(before: caption), 0)
        overlay.drawDuration = max(caption.end - caption.start, 0.1)
        overlay.endTime = holdEnd(for: caption)
        // Leave time for the last letters' fill to fade in before the video ends
        overlay.writeBy = videoDuration - 0.2

        // One line if it fits at (nearly) the set size, otherwise wrap onto two
        layOut(caption.words, wrapped: false, into: &overlay, aspectRatio: aspectRatio)
        if overlay.relativeSize < style.relativeSize * Self.wrapBelowScale, caption.words.count > 1 {
            layOut(caption.words, wrapped: true, into: &overlay, aspectRatio: aspectRatio)
        }
        return overlay
    }

    /// Sets the overlay's text and word timings, shrinking it to fit 90% of the frame width.
    private func layOut(_ words: [CaptionWord], wrapped: Bool, into overlay: inout TextOverlay, aspectRatio: CGFloat) {
        let (text, wordRanges) = Self.join(words, wrapped: wrapped)
        overlay.text = text
        overlay.wordTimings = zip(words, wordRanges).map { word, range in
            WordTiming(characters: range, start: word.start, end: word.end)
        }
        let width = overlay.outline.bounds.width / GlyphOutline.referenceSize
        overlay.relativeSize = width > 0 ? min(style.relativeSize, 0.9 * aspectRatio / width) : style.relativeSize
    }

    /// When a caption starts fading: after its hold, or sooner if the next caption
    /// is close, but never before its own last word has been spoken.
    private func holdEnd(for caption: Caption) -> Double {
        let next = captions.first { $0.start > caption.start }?.start ?? .infinity
        let clear = next - OutlineRenderer.wordLead - TextOverlay.fadeOutDuration
        return max(min(caption.end + Self.hold, clear), caption.end)
    }

    /// When the caption before this one has finished fading, so the two never overlap.
    private func previousGone(before caption: Caption) -> Double {
        guard let previous = captions.last(where: { $0.start < caption.start }) else { return 0 }
        return holdEnd(for: previous) + TextOverlay.fadeOutDuration
    }

    /// Joins words with spaces, optionally wrapping near the middle, and returns
    /// each word's character range in the result.
    private static func join(_ words: [CaptionWord], wrapped: Bool) -> (String, [Range<Int>]) {
        let total = words.map(\.text).joined(separator: " ").count
        var breakBefore: Int?
        if wrapped, words.count > 1 {
            // Break at the word boundary closest to the middle
            var running = 0, best = Int.max
            for index in 1..<words.count {
                running += words[index - 1].text.count + 1
                let distance = abs(running - total / 2)
                if distance < best { best = distance; breakBefore = index }
            }
        }

        var text = ""
        var ranges: [Range<Int>] = []
        for (index, word) in words.enumerated() {
            if index > 0 { text += index == breakBefore ? "\n" : " " }
            let start = text.count
            text += word.text
            ranges.append(start..<text.count)
        }
        return (text, ranges)
    }
}
