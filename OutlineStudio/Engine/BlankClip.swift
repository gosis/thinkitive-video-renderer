//
//  BlankClip.swift
//  OutlineStudio
//

import AVFoundation
import CoreGraphics

/// A still video to start a composition from: plain black, or a photo held for the
/// whole duration.
enum BlankClip {
    enum Shape: String, CaseIterable, Identifiable {
        case portrait, landscape, square

        var id: Self { self }

        var title: String {
            switch self {
            case .portrait: "Portrait 9:16"
            case .landscape: "Landscape 16:9"
            case .square: "Square 1:1"
            }
        }

        var size: CGSize {
            switch self {
            case .portrait: CGSize(width: 1080, height: 1920)
            case .landscape: CGSize(width: 1920, height: 1080)
            case .square: CGSize(width: 1080, height: 1080)
            }
        }
    }

    static let durationRange = 1.0...60.0
    private static let framesPerSecond: Int32 = 30

    /// Writes a video of `duration` seconds showing `image` (or black) and returns its
    /// temporary URL. `image` should already be upright and `size` pixels.
    static func make(duration: Double, size: CGSize, image: CGImage? = nil) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try await render(duration: duration, size: size, image: image)
        }.value
    }

    /// Video dimensions for a photo: its shape, at most 1920 pixels on the long side,
    /// rounded to even numbers as video encoders require.
    static func size(forImageOfSize size: CGSize) -> CGSize {
        let scale = min(1920 / max(size.width, size.height), 1)
        func even(_ value: CGFloat) -> CGFloat { max(2, (value * scale / 2).rounded() * 2) }
        return CGSize(width: even(size.width), height: even(size.height))
    }

    private static func render(duration: Double, size: CGSize, image: CGImage?) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "Still-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        guard let pool = adaptor.pixelBufferPool else { throw CocoaError(.fileWriteUnknown) }
        var created: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &created)
        guard let frame = created else { throw CocoaError(.fileWriteUnknown) }
        paint(frame, size: size, image: image)

        // Every frame is the same still picture, so one buffer is appended repeatedly
        let frameCount = max(Int(duration * Double(framesPerSecond)), 1)
        for index in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            adaptor.append(frame, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: framesPerSecond))
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
        return url
    }

    private static func paint(_ buffer: CVPixelBuffer, size: CGSize, image: CGImage?) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                      width: Int(size.width),
                                      height: Int(size.height),
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        if let image {
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(origin: .zero, size: size))
        }
    }
}
