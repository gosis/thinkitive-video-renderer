//
//  SampleClip.swift
//  OutlineStudio
//

import Foundation

/// A short clip bundled with the app so the editor can be tried without footage:
/// NASA astronaut Christina Koch talking to camera, in portrait, 11 seconds. See
/// `SampleMedia/CREDITS.md`.
enum SampleClip {
    static var url: URL? {
        Bundle.main.url(forResource: "SampleClip", withExtension: "mp4")
    }

    /// The sample opens with its speech already captioned, styled as a showcase:
    /// written in script by a pencil, without a shadow.
    static var captionLayer: CaptionLayer {
        var layer = CaptionLayer(words: transcript)
        layer.style.fontName = "HersheyScript"
        layer.style.pointer = .pencil
        layer.style.shadowEnabled = false
        return layer
    }

    /// What she says, with each word's timing. Captured with `SpeechCaptioner` and
    /// tidied by hand (capitalisation, punctuation, and two merged words split), so
    /// the sample works offline and without asking for speech permission.
    private static let transcript: [CaptionWord] = [
        CaptionWord(text: "I", start: 0.04, end: 0.21),
        CaptionWord(text: "was", start: 0.21, end: 0.38),
        CaptionWord(text: "inspired", start: 0.46, end: 0.86),
        CaptionWord(text: "by", start: 0.88, end: 1.05),
        CaptionWord(text: "everything", start: 1.08, end: 1.50),
        CaptionWord(text: "I", start: 1.50, end: 1.53),
        CaptionWord(text: "learned", start: 1.53, end: 1.72),
        CaptionWord(text: "about", start: 1.84, end: 2.10),
        CaptionWord(text: "Goddard:", start: 2.50, end: 2.98),
        CaptionWord(text: "Earth", start: 3.22, end: 3.51),
        CaptionWord(text: "science,", start: 3.51, end: 3.95),
        CaptionWord(text: "space", start: 4.02, end: 4.45),
        CaptionWord(text: "science,", start: 4.50, end: 4.96),
        CaptionWord(text: "astrophysics,", start: 5.02, end: 6.04),
        CaptionWord(text: "geology,", start: 6.12, end: 6.92),
        CaptionWord(text: "everything", start: 7.24, end: 7.78),
        CaptionWord(text: "cool", start: 7.94, end: 8.25),
        CaptionWord(text: "about", start: 8.25, end: 8.48),
        CaptionWord(text: "the", start: 8.52, end: 8.58),
        CaptionWord(text: "universe", start: 8.64, end: 9.06),
        CaptionWord(text: "feels", start: 9.12, end: 9.33),
        CaptionWord(text: "like", start: 9.33, end: 9.54),
        CaptionWord(text: "it", start: 9.54, end: 9.63),
        CaptionWord(text: "was", start: 9.63, end: 9.76),
        CaptionWord(text: "happening", start: 9.80, end: 10.18),
        CaptionWord(text: "at", start: 10.32, end: 10.48),
        CaptionWord(text: "Goddard.", start: 10.56, end: 11.06),
    ]
}
