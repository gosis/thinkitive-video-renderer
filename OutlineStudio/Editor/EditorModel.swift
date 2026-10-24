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
    var selectedID: TextOverlay.ID?
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

    // MARK: Export

    func export() async {
        guard let videoURL else { return }
        if isPlaying {
            togglePlayback()
        }
        exportState = .rendering(0)
        do {
            let output = try await VideoExporter.export(videoAt: videoURL, overlays: overlays) { [weak self] progress in
                self?.exportState = .rendering(progress)
            }
            try await VideoExporter.saveToPhotos(videoAt: output)
            exportState = .saved
        } catch {
            exportState = .failed(error.localizedDescription)
        }
    }
}
