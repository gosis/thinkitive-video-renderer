//
//  Theme.swift
//  OutlineStudio
//

import SwiftUI
import UIKit

/// Editor palette.
///
/// Graphite neutrals keep attention on the footage, a warm coral accent marks
/// actions and selection, cyan marks clips on the timeline and amber the playhead —
/// the same roles colour plays in pro editing tools. Every token has a light and a
/// dark value and resolves through the current trait collection.
enum Theme {
    /// Letterbox area behind the video preview.
    static let canvas        = Color(light: 0xDCDFE5, dark: 0x08090B)
    static let background    = Color(light: 0xF4F5F7, dark: 0x111318)
    static let surface       = Color(light: 0xFFFFFF, dark: 0x1A1D23)
    static let surfaceRaised = Color(light: 0xECEEF2, dark: 0x252932)
    static let hairline      = Color(light: 0xD5D9E0, dark: 0x30343F)

    static let textPrimary   = Color(light: 0x15171C, dark: 0xF1F2F4)
    static let textSecondary = Color(light: 0x5D6472, dark: 0x8E96A6)

    static let accent        = Color(light: 0xE0482B, dark: 0xFF6A4D)
    static let onAccent      = Color.white
    static let clip          = Color(light: 0x0F8FB0, dark: 0x3CC6E6)
    static let playhead      = Color(light: 0xE8A400, dark: 0xFFCE3D)

    enum Radius {
        static let panel: CGFloat = 16
        static let control: CGFloat = 10
    }
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
