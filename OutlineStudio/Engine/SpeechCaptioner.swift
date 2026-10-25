//
//  SpeechCaptioner.swift
//  OutlineStudio
//

import AVFoundation
import Speech

/// Transcribes a video's speech on device, with the time each word is spoken.
enum SpeechCaptioner {
    enum CaptionError: LocalizedError {
        case noAudio
        case languageUnavailable
        case permissionDenied
        case noSpeech

        var errorDescription: String? {
            switch self {
            case .noAudio: "This video has no sound to caption."
            case .languageUnavailable: "English speech recognition isn't available on this device."
            case .permissionDenied: "Allow speech recognition for Inkcap in Settings to make captions."
            case .noSpeech: "No speech was found in this video."
            }
        }
    }

    private static let english = Locale(identifier: "en-US")

    static func transcribeWords(inVideoAt url: URL) async throws -> [CaptionWord] {
        let audioURL = try await extractAudio(fromVideoAt: url)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        // The newer on-device model handles long audio best, but it isn't
        // available everywhere (including the Simulator)
        let words: [CaptionWord]
        if SpeechTranscriber.isAvailable,
           let locale = await SpeechTranscriber.supportedLocale(equivalentTo: english) {
            words = try await transcribeWithSpeechAnalyzer(audioAt: audioURL, locale: locale)
        } else {
            words = try await transcribeWithRecognizer(audioAt: audioURL)
        }
        guard !words.isEmpty else { throw CaptionError.noSpeech }
        return VoiceActivity(audioAt: audioURL)?.tighten(words) ?? words
    }

    // MARK: SpeechAnalyzer (iOS 26 on-device model)

    private static func transcribeWithSpeechAnalyzer(audioAt audioURL: URL, locale: Locale) async throws -> [CaptionWord] {
        let transcriber = SpeechTranscriber(locale: locale,
                                            transcriptionOptions: [],
                                            reportingOptions: [],
                                            attributeOptions: [.audioTimeRange])

        // The speech model is downloaded by the system the first time it's needed
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installation.downloadAndInstall()
        }

        let audioFile = try AVAudioFile(forReading: audioURL)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collector = Task {
            var words: [CaptionWord] = []
            for try await result in transcriber.results {
                words += Self.words(in: result.text)
            }
            return words
        }

        if let end = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        return try await collector.value
    }

    // MARK: SFSpeechRecognizer (fallback)

    private static func transcribeWithRecognizer(audioAt audioURL: URL) async throws -> [CaptionWord] {
        guard await requestAuthorization() == .authorized else { throw CaptionError.permissionDenied }
        guard let recognizer = SFSpeechRecognizer(locale: english), recognizer.isAvailable else {
            throw CaptionError.languageUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

        // Results arrive one phrase at a time and only the last is marked final, so
        // gather them all. A result replaces anything from its own start onward,
        // which also covers a refined version of the same phrase.
        return try await withCheckedThrowingContinuation { continuation in
            var words: [CaptionWord] = []
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let result {
                    let phrase = result.bestTranscription.segments.map { segment in
                        CaptionWord(text: segment.substring,
                                    start: segment.timestamp,
                                    end: segment.timestamp + segment.duration)
                    }
                    if let first = phrase.first {
                        words.removeAll { $0.end > first.start + 0.01 }
                        words += phrase
                    }
                    if result.isFinal {
                        finished = true
                        continuation.resume(returning: words)
                    }
                } else if let error {
                    finished = true
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    /// Splits a transcription into words, using the time ranges attached to its runs.
    ///
    /// Runs are tokens: a new word usually begins with a space, while punctuation and
    /// word pieces attach to the word before them.
    private static func words(in text: AttributedString) -> [CaptionWord] {
        var words: [CaptionWord] = []
        var startsNewWord = true
        for run in text.runs {
            let token = String(text[run.range].characters)
            guard let range = run.audioTimeRange else {
                startsNewWord = startsNewWord || token.first?.isWhitespace == true
                continue
            }
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                startsNewWord = true
                continue
            }
            let start = range.start.seconds, end = range.end.seconds
            let isPunctuation = trimmed.allSatisfy { $0.isPunctuation }
            if words.isEmpty || ((startsNewWord || token.first?.isWhitespace == true) && !isPunctuation) {
                words.append(CaptionWord(text: trimmed, start: start, end: end))
            } else {
                words[words.count - 1].text += trimmed
                words[words.count - 1].end = max(words[words.count - 1].end, end)
            }
            startsNewWord = token.last?.isWhitespace == true
        }
        return words
    }

    /// Copies the video's sound track to a temporary `.m4a` the analyzer can read.
    private static func extractAudio(fromVideoAt url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty,
              let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw CaptionError.noAudio
        }
        let output = FileManager.default.temporaryDirectory.appending(path: "Audio-\(UUID().uuidString).m4a")
        try await session.export(to: output, as: .m4a)
        return output
    }
}

/// Where in the audio someone is actually speaking.
///
/// Recognizers' word times can be loose (some place each word's end at the next
/// word's start, folding pauses into words). Measuring loudness in the voice band
/// lets each word be trimmed to the part that's really voiced.
private struct VoiceActivity {
    /// Analysis window, in seconds.
    private static let window = 0.02

    private let voiced: [Bool]

    init?(audioAt url: URL) {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let windowLength = Int(sampleRate * Self.window)
        guard windowLength > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_384) else { return nil }

        // A one-pole high-pass at ~250 Hz removes rumble and much of a music bed
        let rc = 1 / (2 * Double.pi * 250), alpha = Float(rc / (rc + 1 / sampleRate))
        var previousInput: Float = 0, previousOutput: Float = 0
        var sumOfSquares: Float = 0, count = 0
        var levels: [Float] = []

        while file.framePosition < file.length {
            guard (try? file.read(into: buffer)) != nil, buffer.frameLength > 0,
                  let samples = buffer.floatChannelData?[0] else { break }
            for i in 0..<Int(buffer.frameLength) {
                let output = alpha * (previousOutput + samples[i] - previousInput)
                previousInput = samples[i]
                previousOutput = output
                sumOfSquares += output * output
                count += 1
                if count == windowLength {
                    levels.append(10 * log10(max(sumOfSquares / Float(count), 1e-10)))
                    sumOfSquares = 0
                    count = 0
                }
            }
        }
        guard levels.count > 10 else { return nil }

        // Threshold relative to this clip's own noise floor and loudest speech
        let sorted = levels.sorted()
        let floor = sorted[sorted.count * 15 / 100], peak = sorted[sorted.count * 95 / 100]
        let threshold = floor + max(6, (peak - floor) * 0.35)
        voiced = levels.map { $0 > threshold }
    }

    /// Trims each word to where it's voiced. When a word's range spans a real
    /// pause, the boundary was misplaced, so the longest voiced stretch is kept.
    /// Words with no voiced audio keep their original times.
    func tighten(_ words: [CaptionWord]) -> [CaptionWord] {
        words.map { word in
            let first = max(Int(word.start / Self.window), 0)
            let last = min(Int(word.end / Self.window), voiced.count - 1)
            guard first <= last, let run = longestVoicedRun(in: first...last) else { return word }
            let trimmedStart = max(word.start, Double(run.lowerBound) * Self.window - 0.02)
            let trimmedEnd = min(word.end, Double(run.upperBound + 1) * Self.window + 0.02)
            guard trimmedEnd - trimmedStart >= 0.08 else { return word }
            return CaptionWord(text: word.text, start: trimmedStart, end: trimmedEnd)
        }
    }

    /// Voiced windows grouped into stretches, bridging gaps shorter than ~0.2s
    /// (stop consonants, breaths), and the longest one returned.
    private func longestVoicedRun(in range: ClosedRange<Int>) -> ClosedRange<Int>? {
        let bridge = Int(0.2 / Self.window)
        var runs: [ClosedRange<Int>] = []
        for index in range where voiced[index] {
            if let last = runs.last, index - last.upperBound <= bridge {
                runs[runs.count - 1] = last.lowerBound...index
            } else {
                runs.append(index...index)
            }
        }
        return runs.max { $0.count < $1.count }
    }
}
