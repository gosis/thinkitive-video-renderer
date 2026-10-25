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
    /// The shadow is a wider, dark stroke under the line, as subtitles use.
    private static let shadowWidthScale: CGFloat = 2.6
    private static let shadowColor = CGColor(gray: 0, alpha: 0.55)

    /// The background box fades in over this long as the text starts.
    private static let backgroundFade = 0.2

    /// Words start writing slightly before they're heard, which reads as in sync.
    static let wordLead = 0.06
    /// Writing time per word: most of its spoken length, within these bounds, so
    /// quick words stay legible and long ones don't drag.
    private static let wordDurationRange = 0.18...0.6
    /// Progress this close to the end counts as finished, so no pointer is left behind.
    static let finishedTolerance = 0.001
    /// The smooth pen never trails a spoken word by more than this, in seconds.
    private static let smoothMaxLag = 0.5
    /// How long a glyph's fill takes to fade in once its outline is traced.
    private static let glyphFillFade = 0.15

    static func draw(_ overlay: TextOverlay, at time: Double, in context: CGContext, videoSize: CGSize) {
        let opacity = overlay.opacity(at: time)
        guard opacity > 0, time >= overlay.startTime else { return }

        context.saveGState()
        defer { context.restoreGState() }
        context.setAlpha(opacity)
        context.setStrokeColor(overlay.strokeColor)
        context.setFillColor(overlay.fillColor)
        context.setLineWidth(overlay.strokeWidth(in: videoSize))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if overlay.backgroundEnabled {
            drawBackground(overlay, at: time, in: context, videoSize: videoSize, opacity: opacity)
        }

        if let timings = overlay.wordTimings {
            drawWordByWord(overlay, timings: timings, at: time, in: context, videoSize: videoSize, opacity: opacity)
        } else {
            drawWhole(overlay, at: time, in: context, videoSize: videoSize, opacity: opacity)
        }
    }

    /// Whether anything of the overlay is visible at `time`.
    static func isVisible(_ overlay: TextOverlay, at time: Double) -> Bool {
        overlay.opacity(at: time) > 0 && overlay.strokeProgress(at: time) > 0
    }

    // MARK: Modes

    /// Traces the whole text over `drawDuration`, then fades in the fill.
    private static func drawWhole(_ overlay: TextOverlay, at time: Double, in context: CGContext,
                                  videoSize: CGSize, opacity: Double) {
        let progress = overlay.strokeProgress(at: time)
        guard progress > 0 else { return }
        let transform = overlay.transform(in: videoSize)

        let fillOpacity = overlay.fillOpacity(at: time)
        if fillOpacity > 0 {
            fill(Path(overlay.outline.combined).applying(transform), alpha: opacity * fillOpacity, in: context)
        }
        let paths = overlay.strokePaths.map { Path($0).applying(transform) }
        for path in paths {
            stroke(path.trimmedPath(from: 0, to: progress), of: overlay,
                   lineWidth: overlay.strokeWidth(in: videoSize), in: context)
        }
        for path in paths {
            drawPointer(of: overlay, along: path, progress: progress, at: time, videoSize: videoSize, in: context)
        }
    }

    /// How far one glyph is drawn at a moment, and how much of its fill shows.
    private struct GlyphState {
        let glyph: Int
        let progress: Double
        let fillOpacity: Double
    }

    /// Writes word-timed text, its letters one after another, at the overlay's writing pace.
    private static func drawWordByWord(_ overlay: TextOverlay, timings: [WordTiming], at time: Double,
                                       in context: CGContext, videoSize: CGSize, opacity: Double) {
        let outline = overlay.outline
        let transform = overlay.transform(in: videoSize)

        // Glyphs grouped by the word their character belongs to, in reading order
        var glyphsByWord = Array(repeating: [Int](), count: timings.count)
        for (glyph, character) in outline.glyphCharacters.enumerated() {
            if let word = timings.firstIndex(where: { $0.characters.contains(character) }) {
                glyphsByWord[word].append(glyph)
            }
        }

        let states = switch overlay.writingPace {
        case .synced: syncedStates(overlay, timings: timings, glyphsByWord: glyphsByWord, at: time)
        case .smooth: smoothStates(overlay, timings: timings, glyphsByWord: glyphsByWord, at: time)
        }

        // Glyphs mid-stroke get a pointer once all the text is drawn
        var tips: [(path: Path, progress: CGFloat)] = []
        for state in states where state.progress > 0 {
            // Summed stroke lengths can leave a finished glyph a rounding error short
            let progress = state.progress > 1 - finishedTolerance ? 1 : state.progress
            let path = Path(outline.glyphs[state.glyph]).applying(transform)
            if overlay.drawsFill, state.fillOpacity > 0 {
                fill(path, alpha: opacity * state.fillOpacity, in: context)
            }
            stroke(path.trimmedPath(from: 0, to: progress), of: overlay,
                   lineWidth: overlay.strokeWidth(in: videoSize), in: context)
            if progress < 1 {
                tips.append((path, CGFloat(progress)))
            }
        }
        for tip in tips {
            drawPointer(of: overlay, along: tip.path, progress: tip.progress, at: time, videoSize: videoSize, in: context)
        }
    }

    /// Each word is written in the moment it's spoken.
    private static func syncedStates(_ overlay: TextOverlay, timings: [WordTiming], glyphsByWord: [[Int]],
                                     at time: Double) -> [GlyphState] {
        var states: [GlyphState] = []
        for (word, timing) in timings.enumerated() {
            let writeStart = max(timing.start - wordLead, overlay.startTime)
            let glyphs = glyphsByWord[word]
            guard time >= writeStart, !glyphs.isEmpty else { continue }
            let duration = min(max((timing.end - timing.start) * 0.8, wordDurationRange.lowerBound),
                               wordDurationRange.upperBound)
            let wordProgress = overlay.easing.apply(min((time - writeStart) / duration, 1))
            let perGlyph = duration / Double(glyphs.count)

            for (order, glyph) in glyphs.enumerated() {
                let progress = min(max(wordProgress * Double(glyphs.count) - Double(order), 0), 1)
                guard progress > 0 else { break }
                let traced = writeStart + perGlyph * Double(order + 1)
                states.append(GlyphState(glyph: glyph, progress: progress,
                                         fillOpacity: min(max((time - traced) / glyphFillFade, 0), 1)))
            }
        }
        return states
    }

    /// The pen moves at a steady speed through the whole text, measured by stroke
    /// length. The schedule is planned word by word so the pen never jumps: a word
    /// starts when it's spoken (or when the previous one is finished, if later),
    /// and speeds up rather than fall more than `smoothMaxLag` behind the voice.
    private static func smoothStates(_ overlay: TextOverlay, timings: [WordTiming], glyphsByWord: [[Int]],
                                     at time: Double) -> [GlyphState] {
        let lengths = overlay.outline.glyphLengths
        let wordLengths = glyphsByWord.map { $0.reduce(0) { $0 + Double(lengths[$1]) } }
        let total = wordLengths.reduce(0, +)
        guard total > 0, let first = timings.first, let last = timings.last else { return [] }

        let start = max(first.start - wordLead, overlay.startTime)
        let fade = overlay.endTime ?? (last.end + 1)
        var finish = max(last.end, min(last.end + smoothMaxLag, fade - 0.15))
        if let writeBy = overlay.writeBy {
            finish = max(min(finish, writeBy), start + 0.1)
        }
        let speed = total / max(finish - start, 0.1)

        // When each word's writing starts and ends
        var windows: [(start: Double, end: Double)] = []
        var penFree = start
        for (index, timing) in timings.enumerated() {
            let begin = max(penFree, timing.start - wordLead)
            var deadline = timing.end + smoothMaxLag
            if index == timings.count - 1 { deadline = min(deadline, finish) }
            let end = max(min(begin + wordLengths[index] / speed, deadline), begin + wordDurationRange.lowerBound)
            windows.append((begin, end))
            penFree = end
        }

        // Each glyph takes its share of its word's window, by stroke length
        var states: [GlyphState] = []
        for (word, glyphs) in glyphsByWord.enumerated() where !glyphs.isEmpty {
            let window = windows[word]
            guard time > window.start else { break }
            let duration = max(window.end - window.start, 0.001)
            let wordProgress = min((time - window.start) / duration, 1)
            let pen = wordProgress * wordLengths[word]
            var before = 0.0
            for glyph in glyphs {
                let length = Double(lengths[glyph])
                guard pen > before, length > 0 else { break }
                let progress = min((pen - before) / length, 1)
                // Fill by time from the moment the outline closes, so a word's last
                // letter (where the pen stops) fills too
                let traced = window.start + (before + length) / wordLengths[word] * duration
                let fillOpacity = min(max((time - traced) / glyphFillFade, 0), 1)
                states.append(GlyphState(glyph: glyph, progress: progress, fillOpacity: fillOpacity))
                before += length
            }
        }
        return states
    }

    private static func drawPointer(of overlay: TextOverlay, along path: Path, progress: CGFloat, at time: Double,
                                    videoSize: CGSize, in context: CGContext) {
        guard overlay.pointer != .off else { return }
        PointerRenderer.draw(overlay.pointer, along: path, progress: progress, time: time,
                             color: overlay.strokeColor,
                             lineWidth: overlay.strokeWidth(in: videoSize),
                             fontSize: overlay.fontSize(in: videoSize),
                             in: context)
    }

    /// A rounded box behind each line, padded around the text and its line width.
    private static func drawBackground(_ overlay: TextOverlay, at time: Double, in context: CGContext,
                                       videoSize: CGSize, opacity: Double) {
        let outline = overlay.outline
        let fontSize = overlay.fontSize(in: videoSize)
        let lineWidth = overlay.strokeWidth(in: videoSize)
        let transform = overlay.transform(in: videoSize)

        context.saveGState()
        context.setFillColor(overlay.backgroundColor)
        for (box, firstCharacter) in zip(outline.lineBoxes, outline.lineFirstCharacters) {
            // Word-timed text reveals each line's box as that line starts writing
            let lineStart = overlay.wordTimings?
                .first { $0.characters.contains(firstCharacter) }
                .map { max($0.start - wordLead, overlay.startTime) } ?? overlay.startTime
            let appear = min(max((time - lineStart) / backgroundFade, 0), 1)
            guard appear > 0 else { continue }

            let rect = box.applying(transform).insetBy(dx: -(fontSize * 0.28 + lineWidth), dy: -lineWidth / 2)
            let corner = min(fontSize * 0.22, rect.height / 2)
            context.setAlpha(opacity * appear)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
            context.fillPath()
        }
        context.restoreGState()
    }

    // MARK: Drawing

    private static func fill(_ path: Path, alpha: Double, in context: CGContext) {
        context.saveGState()
        context.setAlpha(alpha)
        context.addPath(path.cgPath)
        context.fillPath()
        context.restoreGState()
    }

    /// Strokes with the context's current line settings, over a dark halo when the
    /// overlay has a shadow.
    private static func stroke(_ path: Path, of overlay: TextOverlay, lineWidth: CGFloat, in context: CGContext) {
        if overlay.shadowEnabled {
            context.saveGState()
            context.setStrokeColor(shadowColor)
            context.setLineWidth(lineWidth * shadowWidthScale)
            context.addPath(path.cgPath)
            context.strokePath()
            context.restoreGState()
        }
        context.addPath(path.cgPath)
        context.strokePath()
    }
}
