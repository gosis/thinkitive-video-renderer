//
//  Project.swift
//  OutlineStudio
//

import Foundation

/// A saved composition: one video plus everything written on it.
struct Project: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String
    var created = Date.now
    var modified = Date.now
    /// The video's file name inside the project folder.
    var videoFileName: String
    var duration: Double = 0
    var overlays: [TextOverlay] = []
    var captionLayer: CaptionLayer?
}
