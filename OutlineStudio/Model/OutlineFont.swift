//
//  OutlineFont.swift
//  OutlineStudio
//

import UIKit

/// A typeface the text can be drawn in.
struct OutlineFont: Identifiable, Hashable {
    enum Kind {
        /// Bundled stroke font: each letter is drawn as one pen line.
        case singleLine
        /// System font: the letter's border is traced, then optionally filled.
        case outline

        var title: String {
            switch self {
            case .singleLine: "Single line"
            case .outline: "Outline"
            }
        }

        /// Fits the vertical label in the font picker.
        var shortTitle: String {
            switch self {
            case .singleLine: "Line"
            case .outline: "Outline"
            }
        }

        /// Line width that suits the kind, as a fraction of the font size.
        var defaultStrokeWidthRatio: CGFloat {
            switch self {
            case .singleLine: 0.06
            case .outline: 0.025
            }
        }
    }

    /// PostScript name for outline fonts, bundle resource name for single-line fonts.
    let postScriptName: String
    let displayName: String
    var kind = Kind.outline

    var id: String { postScriptName }

    static let singleLine: [OutlineFont] = [
        OutlineFont(postScriptName: "HersheyScript", displayName: "Script", kind: .singleLine),
        OutlineFont(postScriptName: "CursiveScript", displayName: "Cursive", kind: .singleLine),
        OutlineFont(postScriptName: "ReliefSingleLine", displayName: "Relief", kind: .singleLine),
        OutlineFont(postScriptName: "HersheySans", displayName: "Sans", kind: .singleLine),
        OutlineFont(postScriptName: "HersheySerif", displayName: "Serif", kind: .singleLine),
        OutlineFont(postScriptName: "HersheyGothic", displayName: "Gothic", kind: .singleLine),
    ]

    static let outline: [OutlineFont] = [
        OutlineFont(postScriptName: "SnellRoundhand-Bold", displayName: "Snell"),
        OutlineFont(postScriptName: "AvenirNext-Heavy", displayName: "Heavy"),
        OutlineFont(postScriptName: "Futura-Bold", displayName: "Futura"),
        OutlineFont(postScriptName: "Didot-Bold", displayName: "Didot"),
        OutlineFont(postScriptName: "BradleyHandITCTT-Bold", displayName: "Hand"),
        OutlineFont(postScriptName: "Noteworthy-Bold", displayName: "Note"),
        OutlineFont(postScriptName: "Zapfino", displayName: "Zapfino"),
        OutlineFont(postScriptName: "AmericanTypewriter-Bold", displayName: "Typewriter"),
        OutlineFont(postScriptName: "MarkerFelt-Wide", displayName: "Marker"),
        OutlineFont(postScriptName: "Chalkduster", displayName: "Chalk"),
        OutlineFont(postScriptName: "Copperplate-Bold", displayName: "Plate"),
        OutlineFont(postScriptName: "Georgia-BoldItalic", displayName: "Georgia"),
    ].filter { UIFont(name: $0.postScriptName, size: 12) != nil }

    static let all = singleLine + outline

    static var defaultFont: OutlineFont {
        all.first ?? OutlineFont(postScriptName: "Helvetica-Bold", displayName: "Helvetica")
    }

    private static let byName = Dictionary(all.map { ($0.postScriptName, $0) }, uniquingKeysWith: { first, _ in first })

    static func named(_ name: String) -> OutlineFont? {
        byName[name]
    }
}
