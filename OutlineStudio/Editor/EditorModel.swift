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
    var isLoading = false

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
    @ObservationIgnored private let fontsReady: Task<Void, Never>
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    let store = ProjectStore()
    /// The project being edited; nil in the library.
    private(set) var project: Project?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    init() {
        // Font parsing takes a moment; do it off the main thread before anyone needs it
        fontsReady = Task.detached(priority: .userInitiated) { StrokeFont.preloadAll() }

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
        return captionLayer.captions.map { captionLayer.overlay(for: $0, aspectRatio: aspectRatio, videoDuration: duration) }
    }

    // MARK: Media

    // MARK: Projects

    /// Starts a project from a video, e.g. one picked from Photos or Files.
    func importVideo(from url: URL) async {
        let name = "Video " + Date.now.formatted(date: .abbreviated, time: .shortened)
        await startProject(fromVideoAt: url, name: name)
    }

    func loadSampleClip() async {
        guard let url = SampleClip.url else {
            alertMessage = "The sample clip is missing from the app."
            return
        }
        guard await startProject(fromVideoAt: url, name: "Astronaut sample") else { return }
        // Only the transcribed speech, no placeholder text
        overlays = []
        selectedID = nil
        captionLayer = SampleClip.captionLayer
        saveProject()
    }

    /// Starts from a black video of `duration` seconds at `size`.
    func newComposition(duration: Double, size: CGSize) async {
        isLoading = true
        do {
            let url = try await BlankClip.make(duration: duration, size: size)
            defer { try? FileManager.default.removeItem(at: url) }
            await startProject(fromVideoAt: url, name: "Blank video \(Int(duration))s")
        } catch {
            isLoading = false
            alertMessage = error.localizedDescription
        }
    }

    /// Starts from a photo held still for `duration` seconds, at the photo's own shape.
    func newComposition(fromImage image: UIImage, duration: Double) async {
        isLoading = true
        do {
            let size = BlankClip.size(forImageOfSize: CGSize(width: image.size.width * image.scale,
                                                             height: image.size.height * image.scale))
            // Redraw so the pixels are upright (photos often carry an orientation flag) and sized
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            let url = try await BlankClip.make(duration: duration, size: size, image: upright.cgImage)
            defer { try? FileManager.default.removeItem(at: url) }
            let name = "Photo " + Date.now.formatted(date: .abbreviated, time: .shortened)
            await startProject(fromVideoAt: url, name: name)
        } catch {
            isLoading = false
            alertMessage = error.localizedDescription
        }
    }

    /// Copies the video into a new saved project and opens it.
    @discardableResult
    private func startProject(fromVideoAt url: URL, name: String) async -> Bool {
        isLoading = true
        saveProject()
        do {
            let created = try await store.create(videoAt: url, name: name)
            // Fonts load in the background; wait here rather than stall the first draw
            await fontsReady.value
            overlays = []
            await loadVideo(from: store.videoURL(for: created))
            guard videoURL == store.videoURL(for: created) else {
                store.delete(created)
                return false
            }
            project = created
            saveProject()
            return true
        } catch {
            isLoading = false
            alertMessage = error.localizedDescription
            return false
        }
    }

    /// Reopens a saved project exactly as it was left.
    func openProject(_ saved: Project) async {
        isLoading = true
        saveProject()
        await fontsReady.value
        await loadVideo(from: store.videoURL(for: saved))
        guard videoURL == store.videoURL(for: saved) else { return }
        overlays = saved.overlays
        overlays.indices.forEach { overlays[$0].wrapAspectRatio = aspectRatio }
        captionLayer = saved.captionLayer
        selectedID = nil
        selectedCaptionID = nil
        project = saved
    }

    /// Saves and goes back to the library.
    func closeProject() {
        saveProject()
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        project = nil
        videoURL = nil
        overlays = []
        captionLayer = nil
        selectedID = nil
        selectedCaptionID = nil
        currentTime = 0
        duration = 0
    }

    /// Writes the open project to disk now.
    func saveProject() {
        saveTask?.cancel()
        guard var current = project else { return }
        current.overlays = overlays
        current.captionLayer = captionLayer
        current.duration = duration
        store.save(current)
        project = current
    }

    /// Saves shortly after edits stop, so dragging a slider doesn't write on every frame.
    func scheduleSave() {
        guard project != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled else { return }
            self?.saveProject()
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
            // Existing text wraps to the new video's shape
            overlays.indices.forEach { overlays[$0].wrapAspectRatio = aspectRatio }

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
        overlay.wrapAspectRatio = aspectRatio
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
    /// A text layer, looked up by ID on every read and write. Views must not hold a
    /// layer by array position: after a delete a stale position reads past the end.
    func overlayBinding(for id: TextOverlay.ID) -> Binding<TextOverlay> {
        Binding { [self] in
            overlays.first { $0.id == id } ?? TextOverlay(id: id)
        } set: { [self] edited in
            guard let index = overlays.firstIndex(where: { $0.id == id }) else { return }
            overlays[index] = edited
        }
    }

    func moveOverlay(_ id: TextOverlay.ID, to position: CGPoint) {
        guard let index = overlays.firstIndex(where: { $0.id == id }) else { return }
        overlays[index].position = position
    }

    func captionBinding(for id: Caption.ID) -> Binding<TextOverlay> {
        Binding { [self] in
            guard let layer = captionLayer, let caption = layer.captions.first(where: { $0.id == id }) else {
                return TextOverlay()
            }
            // Show the plain sentence for editing rather than the wrapped layout
            var overlay = layer.overlay(for: caption, aspectRatio: aspectRatio, videoDuration: duration)
            overlay.text = caption.text
            return overlay
        } set: { [self] edited in
            guard var layer = captionLayer,
                  let index = layer.captions.firstIndex(where: { $0.id == id }) else { return }
            let current = layer.overlay(for: layer.captions[index], aspectRatio: aspectRatio, videoDuration: duration)

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
            if edited.pointer != current.pointer { layer.style.pointer = edited.pointer }
            if edited.writingPace != current.writingPace { layer.style.writingPace = edited.writingPace }
            captionLayer = layer
        }
    }

    /// Back to watching: nothing selected and the keyboard put away.
    func clearSelection() {
        dismissKeyboard()
        selectedID = nil
        selectedCaptionID = nil
    }

    /// Selects a caption and moves the playhead into it so it's on screen.
    func selectCaption(_ id: Caption.ID) {
        selectedCaptionID = id
        if let caption = captionLayer?.captions.first(where: { $0.id == id }),
           currentTime < caption.start || currentTime > caption.end + CaptionLayer.hold {
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
