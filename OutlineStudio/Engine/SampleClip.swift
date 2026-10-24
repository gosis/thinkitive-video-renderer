//
//  SampleClip.swift
//  OutlineStudio
//

import Foundation

/// A short clip bundled with the app so the editor can be tried without footage:
/// NASA astronaut Christina Koch talking to camera, in portrait. See
/// `SampleMedia/CREDITS.md`.
enum SampleClip {
    static var url: URL? {
        Bundle.main.url(forResource: "SampleClip", withExtension: "mp4")
    }
}
