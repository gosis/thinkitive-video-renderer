//
//  EditorModel.swift
//  OutlineStudio
//

import AVFoundation
import Observation
import SwiftUI

@MainActor
@Observable
final class EditorModel {
    enum ExportState: Equatable {
        case idle
        case rendering(Double)
        case saved
        case failed(String)
    }

    private(set) var videoURL: URL?
    /// Display size of the video with its orientation applied.
    private(set) var renderSize = CGSize(width: 1080, height: 1920)
    private(set) var duration: Double = 0
    private(set) var currentTime: Double = 0
    private(set) var isPlaying = false
    private(set) var isLoading = false

    var overlays: [TextOverlay] = []
    var captionLayer: CaptionLayer?
    /// Selected text overlay. Selecting a text clears any selected caption.
    var selectedID: TextOverlay.ID? {
        didSet { if selectedID != nil { selectedCaptionID = nil } }
    }
    /// Selected caption. Selecting a caption clears any selected text.
    var selectedCaptionID: Caption.ID? {
        didSet { if selectedCaptionID != nil { selectedID = nil } }
    }
    private(set) var isCaptioning = false
    var exportState = ExportState.idle
    var alertMessage: String?

    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    init() {
        player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 60), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.currentTime = time.seconds
            }
        }
    }

    var hasVideo: Bool { videoURL != nil }

    var selectedIndex: Int? {
        overlays.firstIndex { $0.id == selectedID }
    }

    var selectedCaptionIndex: Int? {
        captionLayer?.captions.firstIndex { $0.id == selectedCaptionID }
    }

    private var aspectRatio: CGFloat {
        renderSize.height > 0 ? renderSize.width / renderSize.height : 1
    }

    /// Text overlays followed by captions, ready to draw.
    var renderedOverlays: [TextOverlay] {
        overlays + captionOverlays
    }

    var captionOverlays: [TextOverlay] {
        guard let captionLayer else { return [] }
        return captionLayer.captions.map { captionLayer.overlay(for: $0, aspectRatio: aspectRatio) }
    }

    // MARK: Media

    func loadSampleClip() async {
        isLoading = true
        do {
            await loadVideo(from: try await SampleClip.make())
        } catch {
            isLoading = false
            alertMessage = error.localizedDescription
        }
    }

    func loadVideo(from url: URL) async {
        isLoading = true
        defer { isLoading = false }

        let asset = AVURLAsset(url: url)
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                alertMessage = "That file has no video track."
                return
            }
            let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
            let assetDuration = try await asset.load(.duration)

            let oriented = naturalSize.applying(transform)
            renderSize = CGSize(width: abs(oriented.width), height: abs(oriented.height))
            duration = assetDuration.seconds

            let item = AVPlayerItem(asset: asset)
            observeEnd(of: item)
            player.replaceCurrentItem(with: item)
            player.pause()
            isPlaying = false
            currentTime = 0
            videoURL = url

            captionLayer = nil
            selectedCaptionID = nil
            if overlays.isEmpty {
                addOverlay()
            } else {
                overlays.indices.forEach { fitTiming(of: &overlays[$0]) }
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func observeEnd(of item: AVPlayerItem) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                             object: item,
                                                             queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isPlaying = false
            }
        }
    }

    // MARK: Playback

    func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
            return
        }
        if currentTime >= duration - 0.05 {
            seek(to: 0)
        }
        player.play()
        isPlaying = true
    }

    /// Seeks while the user drags the playhead, pausing playback.
    func scrub(to time: Double) {
        if isPlaying {
            player.pause()
            isPlaying = false
        }
        seek(to: time)
    }

    private func seek(to time: Double) {
        let clamped = min(max(time, 0), duration)
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero)
    }

    // MARK: Overlays

    func addOverlay() {
        var overlay = TextOverlay()
        overlay.position.y = 0.4 + 0.1 * CGFloat(overlays.count % 3)
        overlay.startTime = currentTime
        fitTiming(of: &overlay)
        overlays.append(overlay)
        selectedID = overlay.id
    }

    func duplicateSelected() {
        guard let index = selectedIndex else { return }
        var copy = overlays[index]
        copy.id = UUID()
        copy.position.y = min(copy.position.y + 0.08, 0.95)
        overlays.insert(copy, at: index + 1)
        selectedID = copy.id
    }

    func deleteSelected() {
        if let index = selectedCaptionIndex, var layer = captionLayer {
            layer.captions.remove(at: index)
            captionLayer = layer.captions.isEmpty ? nil : layer
            selectedCaptionID = captionLayer.flatMap { layer in
                layer.captions.indices.contains(index) ? layer.captions[index].id : layer.captions.last?.id
            }
            return
        }
        guard let index = selectedIndex else { return }
        overlays.remove(at: index)
        selectedID = overlays.indices.contains(index) ? overlays[index].id : overlays.last?.id
    }

    /// Keeps an overlay's timing inside the current video.
    private func fitTiming(of overlay: inout TextOverlay) {
        guard duration > 0 else { return }
        overlay.drawDuration = min(overlay.drawDuration, max(duration, 0.2))
        overlay.startTime = min(overlay.startTime, max(duration - overlay.drawDuration, 0))
        if let endTime = overlay.endTime, endTime > duration || endTime <= overlay.startTime {
            overlay.endTime = nil
        }
    }

    // MARK: Captions

    /// Transcribes the video's speech and replaces the caption layer.
    func generateCaptions() async {
        guard let videoURL, !isCaptioning else { return }
        if isPlaying {
            togglePlayback()
        }
        isCaptioning = true
        defer { isCaptioning = false }
        do {
            let words = try await SpeechCaptioner.transcribeWords(inVideoAt: videoURL)
            var layer = CaptionLayer(words: words)
            // Keep the look of an existing caption layer when regenerating
            if let existing = captionLayer {
                layer.style = existing.style
            }
            captionLayer = layer
            if let first = layer.captions.first {
                selectCaption(first.id)
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    /// The selected caption as an editable overlay. Text and timing edits apply to
    /// that caption; style edits apply to every caption.
    func captionBinding(for id: Caption.ID) -> Binding<TextOverlay> {
        Binding { [self] in
            guard let layer = captionLayer, let caption = layer.captions.first(where: { $0.id == id }) else {
                return TextOverlay()
            }
            // Show the plain sentence for editing rather than the wrapped layout
            var overlay = layer.overlay(for: caption, aspectRatio: aspectRatio)
            overlay.text = caption.text
            return overlay
        } set: { [self] edited in
            guard var layer = captionLayer,
                  let index = layer.captions.firstIndex(where: { $0.id == id }) else { return }
            let current = layer.overlay(for: layer.captions[index], aspectRatio: aspectRatio)

            if edited.text != layer.captions[index].text {
                layer.captions[index].setText(edited.text)
            }
            if edited.startTime != current.startTime || edited.endTime != current.endTime {
                let start = edited.startTime
                let end = max((edited.endTime ?? duration) - CaptionLayer.hold, start + 0.1)
                layer.captions[index].retime(start: start, end: end)
            }
            // Only copy style fields that actually changed, so an auto-fitted size
            // doesn't overwrite the layer's size
            if edited.relativeSize != current.relativeSize { layer.style.relativeSize = edited.relativeSize }
            if edited.fontName != current.fontName { layer.style.fontName = edited.fontName }
            if edited.strokeWidthRatio != current.strokeWidthRatio { layer.style.strokeWidthRatio = edited.strokeWidthRatio }
            if edited.strokeColor != current.strokeColor { layer.style.strokeColor = edited.strokeColor }
            if edited.fillEnabled != current.fillEnabled { layer.style.fillEnabled = edited.fillEnabled }
            if edited.fillColor != current.fillColor { layer.style.fillColor = edited.fillColor }
            if edited.shadowEnabled != current.shadowEnabled { layer.style.shadowEnabled = edited.shadowEnabled }
            if edited.backgroundEnabled != current.backgroundEnabled { layer.style.backgroundEnabled = edited.backgroundEnabled }
            if edited.backgroundColor != current.backgroundColor { layer.style.backgroundColor = edited.backgroundColor }
            if edited.position != current.position { layer.style.position = edited.position }
            if edited.easing != current.easing { layer.style.easing = edited.easing }
            captionLayer = layer
        }
    }

    /// Selects a caption and moves the playhead into it so it's on screen.
    func selectCaption(_ id: Caption.ID) {
        selectedCaptionID = id
        if let caption = captionLayer?.captions.first(where: { $0.id == id }),
           currentTime < caption.start || currentTime > caption.end {
            scrub(to: min(caption.start + 0.05, duration))
        }
    }

    /// Moves every caption, since they share one position.
    func moveCaptions(to position: CGPoint) {
        captionLayer?.style.position = position
    }

    // MARK: Export

    func export() async {
        guard let videoURL else { return }
        if isPlaying {
            togglePlayback()
        }
        exportState = .rendering(0)
        do {
            let output = try await VideoExporter.export(videoAt: videoURL, overlays: renderedOverlays) { [weak self] progress in
                self?.exportState = .rendering(progress)
            }
            try await VideoExporter.saveToPhotos(videoAt: output)
            exportState = .saved
        } catch {
            exportState = .failed(error.localizedDescription)
        }
    }
}
