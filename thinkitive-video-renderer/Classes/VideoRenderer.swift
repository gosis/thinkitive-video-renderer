//
//  VideoRenderer.swift
//  LottieVideoDemo
//
//  Created by Gints Osis on 21/06/2023.
//

import Photos
import UIKit

public protocol OverlayRenderable: UIView {
    
    // Provide the frame of animation at the given percentage
    func updateTime(percentage: CGFloat)
}

private extension OverlayRenderable {
    func rectInSize(size:CGSize) -> CGRect {
        
        guard let superView = self.superview else {
            
            return CGRect.zero
        }
        
        let myRect = self.frame
        let superViewFrame = superView.frame
        
        let widthScaleFactor = size.width / superView.frame.size.width
        let heightScaleFactor = size.height / superView.frame.size.height
        
        let averageScaleFactor = (widthScaleFactor + heightScaleFactor) / 2
                
        let newOriginX = myRect.origin.x / superViewFrame.size.width * size.width
        let newOriginY = myRect.origin.y / superViewFrame.size.height * size.height
        let newWidth = myRect.size.width * averageScaleFactor
        let newHeight = myRect.size.height * averageScaleFactor
        
        return CGRect(x: newOriginX,
                      y: newOriginY,
                      width: newWidth,
                      height: newHeight)
    }
    
    func prepareToRenderInRect(rect:CGRect) {
        self.frame = rect
        self.layoutIfNeeded()
    }
}

class VideoRenderer {
    
    private enum VideoRendererError: Error, CustomDebugStringConvertible {
        case failedToProcessPHAsset
        case invalidDuration
        case failedToExtractImage
        case failedToExtractVideo
        case failedToGetOutputImage
        case renderingFailed
        case wrongAssetType
        
        var debugDescription: String {
            switch self {
            case .failedToProcessPHAsset:
                return "Vailed to process PHAsset"
            case .invalidDuration:
                return "Invalid duration provided"
            case .failedToExtractImage:
                return "Failed to extract image from image asset"
            case .failedToExtractVideo:
                return "Failed to extract video from video asset"
            case .failedToGetOutputImage:
                return "Failed to get output image from filter"
            case .renderingFailed:
                return "Rendering failed"
            case .wrongAssetType:
                return "Asset provided was not image or video"
            }
        }
    }
    
    public class func exportVideoAsset(phAsset: PHAsset,
                                       duration: Float,
                                       resolution: CGSize,
                                       overlays:[OverlayRenderable],
                                       completion:@escaping (URL?, Error?) -> ()) {
        
        if duration > 60 || duration < 0.1 {
            let error = VideoRendererError.invalidDuration
            completion(nil, error)
            return
        }
        
        processVideoAsset(phAsset: phAsset,
                          duration: duration,
                          resolution: resolution) { asset, error in
            
            guard let asset = asset else {
                completion(nil, error)
                return
            }
            
            self.exportComposition(asset: asset,
                                   overlays: overlays) { url, error in
                completion(url, error)
            }
        }
    }
    
    public class func saveVideoInPhotos(url:URL, completion: (() -> ())? = nil) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }) { (result, error) in
            self.deleteTemporaryFile(url: url)
            
            DispatchQueue.main.async {
                completion?()
            }
        }
    }
    
    private class func processVideoAsset(phAsset: PHAsset,
                                         duration: Float,
                                         resolution: CGSize,
                                         completion:@escaping (AVAsset?, Error?) -> ()) {
        if phAsset.mediaType == .image {
            let imageRequestOptions = PHImageRequestOptions()
            imageRequestOptions.version = PHImageRequestOptionsVersion.original
            imageRequestOptions.isNetworkAccessAllowed = true
            imageRequestOptions.resizeMode = PHImageRequestOptionsResizeMode.exact
            
            PHImageManager.default().requestImage(for: phAsset, targetSize: resolution, contentMode: PHImageContentMode.aspectFit, options: imageRequestOptions) { (image, userInfo) in
                
                guard let image = image else {
                    
                    return
                }
                
                self.videoAssetFromImage(image: image,
                                         length: TimeInterval(duration)) { (asset) in
                    
                    DispatchQueue.main.async {
                        completion(asset, nil)
                    }
                }
            }
        } else if phAsset.mediaType == .video {
            let videoRequestOptions = PHVideoRequestOptions()
            videoRequestOptions.version = PHVideoRequestOptionsVersion.original
            videoRequestOptions.isNetworkAccessAllowed = true
            
            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: videoRequestOptions) { (asset, audioMix, info) in
                guard let avAsset = asset else {
                    DispatchQueue.main.async {
                        let error = VideoRendererError.failedToExtractVideo
                        completion(nil, error)
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    completion(avAsset, nil)
                }
            }
        } else {
            let error = VideoRendererError.wrongAssetType
            completion(nil, error)
        }
    }
    
    
    private class func exportComposition(asset: AVAsset,
                               overlays:[OverlayRenderable],
                               completion: @escaping (URL?, Error?) -> ()) {
        
        // 1 - Create AVMutableComposition object. This object will hold your AVMutableCompositionTrack instances.
        let composition = AVMutableComposition.init()
        
        // 2 - Add video track
        let videoTrack = composition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let videoAssetTrack = asset.tracks(withMediaType: AVMediaType.video)[0]
        try! videoTrack?.insertTimeRange(CMTimeRange(start: CMTime.zero, duration: asset.duration),
                                         of: videoAssetTrack,
                                         at: CMTime.zero)
        
        // 4 - Create an AVMutableVideoCompositionLayerInstruction for the video track and fix the orientation.
        let videoLayerInstruction = AVMutableVideoCompositionLayerInstruction.init(assetTrack: videoAssetTrack)
        
        var isPortrait = false
        
        let videoTransform = videoAssetTrack.preferredTransform
        
        if videoTransform.a == 0 && videoTransform.b == 1.0 && videoTransform.c == -1.0 && videoTransform.d == 0 {
            isPortrait = true
        }
        
        if videoTransform.a == 0 && videoTransform.b == -1.0 && videoTransform.c == 1.0 && videoTransform.d == 0 {
            isPortrait = true
        }
        
        videoLayerInstruction.setTransform(videoAssetTrack.preferredTransform, at: CMTime.zero)
        videoLayerInstruction.setOpacity(0.0, at: asset.duration)
        
        var size = videoAssetTrack.naturalSize
        
        if isPortrait {
            size = CGSize(width: videoAssetTrack.naturalSize.height, height: videoAssetTrack.naturalSize.width)
        }
        
        let filter = CIFilter(name: "CISourceAtopCompositing")
        for overlay in overlays {
            let rect = overlay.rectInSize(size: size)
            overlay.prepareToRenderInRect(rect: rect)
        }
                        
        let mainComposition = AVMutableVideoComposition(asset: asset) { (request) in
            
            DispatchQueue.main.async {
                
                filter?.setValue(request.sourceImage, forKey: kCIInputBackgroundImageKey)
                
                let seconds = CMTimeGetSeconds(request.compositionTime)
                let percentage = CGFloat(seconds / CMTimeGetSeconds(asset.duration))
                    
                // draw overlays
                UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
                
                let context = UIGraphicsGetCurrentContext()!
                context.setShouldSmoothFonts(true)
                context.setShouldAntialias(true)
                context.setShouldSubpixelQuantizeFonts(true)
                context.setShouldSubpixelPositionFonts(true)
                for overlay in overlays {
                    overlay.updateTime(percentage: percentage)
                    overlay.drawHierarchy(in: overlay.frame, afterScreenUpdates: true)
                }
                let animationImage = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                
                let inputImage = CIImage(cgImage: (animationImage?.cgImage)!)
                
                filter?.setValue(inputImage, forKey: kCIInputImageKey)
                
                guard let outputImage = filter?.outputImage else {
                    let error = VideoRendererError.failedToGetOutputImage
                    request.finish(with: error)
                    completion(nil, error)
                    return
                }
                
                request .finish(with: outputImage, context: nil)
            }
        }
        
        mainComposition.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid
        mainComposition.frameDuration = CMTime(value: 1, timescale:60)
        mainComposition.renderSize = size
        
        // 6 - create path where temporary video will be stored
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let documentsDirectory = paths[0]
        
        let name = UUID().uuidString
        let url = URL(fileURLWithPath: documentsDirectory + "/" + name + ".mov")
                
        // 7 - Export the video
        let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        exporter?.outputURL = url
        exporter?.outputFileType = AVFileType.mov
        exporter?.shouldOptimizeForNetworkUse = false
        exporter?.videoComposition = mainComposition
        exporter?.exportAsynchronously {
            if exporter?.status == .completed {
                guard let outputURL = exporter?.outputURL else { return }
                
                completion(outputURL, nil)
            }
            
            if exporter?.status == .failed {
                let error = VideoRendererError.renderingFailed
                completion(nil,  error)
            }
        }
    }
    
    private class func deleteTemporaryFile(url:URL) {
        let fileManager = FileManager.default
        
        do {
            try fileManager.removeItem(at: url)
        } catch {
            NSLog("Can't delete file at %@", url.path)
        }
    }
}

extension VideoRenderer {
    
    class func videoAssetFromImage(image: UIImage,
                                   length: TimeInterval,
                                   completion: @escaping (AVAsset?) -> ()) {
        do {
            let imageSize = image.size
            
            let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
            let documentsDirectory = paths[0]
            
            let name = UUID().uuidString
            let outputFileURL = URL(fileURLWithPath: documentsDirectory + "/" + name + ".mov")
            
            let videoWriter = try AVAssetWriter(outputURL: outputFileURL, fileType: AVFileType.mov)
            let videoSettings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
                                                AVVideoWidthKey: imageSize.width,
                                                AVVideoHeightKey: imageSize.height]
            let videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoWriterInput, sourcePixelBufferAttributes: nil)
            
            
            if !videoWriter.canAdd(videoWriterInput) {
                completion(nil)
                return
            }
            videoWriterInput.expectsMediaDataInRealTime = true
            videoWriter.add(videoWriterInput)
            
            videoWriter.startWriting()
            videoWriter.startSession(atSourceTime: CMTime.zero)
            
            guard let cgImage = image.cgImage else {
                
                completion(nil)
                return
            }
            
            
            
            for i in 0..<Int(length) {
                
                let buffer: CVPixelBuffer = try self.pixelBuffer(fromImage: cgImage, size: imageSize)!
                
                let time = CMTime(seconds: Double(Double(i) / 1),
                                  preferredTimescale: Int32(NSEC_PER_SEC))
                
                while !adaptor.assetWriterInput.isReadyForMoreMediaData {
                    
                    usleep(10)
                }
                adaptor.append(buffer, withPresentationTime: time)
            }
            
            videoWriterInput.markAsFinished()
            videoWriter.finishWriting {
                
                let asset = AVAsset(url: outputFileURL)
                completion(asset)
            }
        } catch {
            
            completion(nil)
        }
    }
    
    class func pixelBuffer(fromImage image: CGImage, size: CGSize) throws -> CVPixelBuffer? {
        let options: CFDictionary = [kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true] as CFDictionary
        var pxbuffer: CVPixelBuffer? = nil
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, options, &pxbuffer)
        
        guard let buffer = pxbuffer, status == kCVReturnSuccess else {
            
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        
        guard let pxdata = CVPixelBufferGetBaseAddress(buffer) else {
            
            return nil
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(data: pxdata, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
        context.concatenate(CGAffineTransform(rotationAngle: 0))
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        
        CVPixelBufferUnlockBaseAddress(buffer, [])
        
        return buffer
    }
}
