//
//  VideoExporter.swift
//  OutlineStudio
//

import AVFoundation
import CoreImage
import Photos

/// Burns text overlays into a video at full resolution.
enum VideoExporter {
    enum ExportError: LocalizedError {
        case unsupportedAsset
        case photoAccessDenied

        var errorDescription: String? {
            switch self {
            case .unsupportedAsset: "This video can't be exported."
            case .photoAccessDenied: "Allow Outline to add to your photo library in Settings to save videos."
            }
        }
    }

    /// Renders `overlays` onto the video at `url` and returns the URL of a temporary `.mov`.
    @MainActor
    static func export(videoAt url: URL,
                       overlays: [TextOverlay],
                       progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let overlays = overlays.filter { !$0.text.isEmpty }

        // Source frames arrive with the track's preferred transform applied,
        // so portrait footage stays upright and matches the preview's render size
        let composition = try await AVMutableVideoComposition.videoComposition(with: asset) { request in
            let time = request.compositionTime.seconds
            guard let overlayImage = overlayImage(for: overlays, at: time, size: request.renderSize) else {
                request.finish(with: request.sourceImage, context: nil)
                return
            }
            request.finish(with: overlayImage.composited(over: request.sourceImage), context: nil)
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.unsupportedAsset
        }
        session.videoComposition = composition

        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "Outline-\(UUID().uuidString).mov")

        let monitor = Task { @MainActor in
            for await state in session.states(updateInterval: 0.1) {
                if case .exporting(let exportProgress) = state {
                    progress(exportProgress.fractionCompleted)
                }
            }
        }
        defer { monitor.cancel() }

        try await session.export(to: outputURL, as: .mov)
        return outputURL
    }

    /// Draws the overlays visible at `time` into a transparent frame, or returns `nil` if none are.
    private static func overlayImage(for overlays: [TextOverlay], at time: Double, size: CGSize) -> CIImage? {
        let visible = overlays.filter { OutlineRenderer.isVisible($0, at: time) }
        guard !visible.isEmpty,
              let context = CGContext(data: nil,
                                      width: Int(size.width),
                                      height: Int(size.height),
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        // Flip to the y-down space the overlays are laid out in
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        for overlay in visible {
            OutlineRenderer.draw(overlay, at: time, in: context, videoSize: size)
        }

        return context.makeImage().map { CIImage(cgImage: $0) }
    }

    /// Moves a rendered video into the photo library.
    static func saveToPhotos(videoAt url: URL) async throws {
        defer { try? FileManager.default.removeItem(at: url) }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportError.photoAccessDenied
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}
