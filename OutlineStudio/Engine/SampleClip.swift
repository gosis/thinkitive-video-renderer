//
//  SampleClip.swift
//  OutlineStudio
//

import AVFoundation
import CoreGraphics

/// Generates a short animated gradient clip so the editor can be tried without footage.
enum SampleClip {
    private static let size = CGSize(width: 720, height: 1280)
    private static let framesPerSecond: Int32 = 30
    private static let seconds: Int32 = 6

    static func make() async throws -> URL {
        try await Task.detached(priority: .userInitiated) { try await render() }.value
    }

    private static func render() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "Sample-\(UUID().uuidString).mov")
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

        let frameCount = framesPerSecond * seconds
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { break }

            draw(into: buffer, progress: Double(frame) / Double(frameCount))
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: framesPerSecond))
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
        return url
    }

    /// A slow dusk gradient with drifting soft lights.
    private static func draw(into buffer: CVPixelBuffer, progress: Double) {
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

        let phase = progress * 2 * .pi
        let colors = [
            CGColor(red: 0.10, green: 0.07 + 0.03 * sin(phase), blue: 0.22, alpha: 1),
            CGColor(red: 0.55 + 0.1 * sin(phase), green: 0.22, blue: 0.35, alpha: 1),
            CGColor(red: 0.98, green: 0.55 + 0.08 * cos(phase), blue: 0.35, alpha: 1),
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.6, 1]) {
            context.drawLinearGradient(gradient,
                                       start: CGPoint(x: size.width * (0.3 + 0.2 * sin(phase)), y: size.height),
                                       end: CGPoint(x: size.width * (0.7 - 0.2 * sin(phase)), y: 0),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }

        for index in 0..<5 {
            let angle = phase + Double(index) * 1.3
            let center = CGPoint(x: size.width * (0.5 + 0.35 * cos(angle)),
                                 y: size.height * (0.5 + 0.3 * sin(angle * 0.7)))
            let radius = 60 + CGFloat(index) * 22
            context.setFillColor(CGColor(red: 1, green: 0.9, blue: 0.8, alpha: 0.08))
            context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                           width: radius * 2, height: radius * 2))
        }
    }
}
