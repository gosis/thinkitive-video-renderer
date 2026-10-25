//
//  OutlineFont.swift
//  OutlineStudio
//

import CoreText
import UIKit

/// A typeface the text can be drawn in.
struct OutlineFont: Identifiable, Hashable {
    enum Kind {
        /// Bundled stroke font: each letter is drawn as one pen line.
        case singleLine
        /// Regular font: the letter's border is traced, then optionally filled.
        case outline

        var title: String {
            switch self {
            case .singleLine: "Single line"
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

    /// What a font is for; the font picker is organised by these.
    enum Category: String, CaseIterable, Identifiable {
        case handwriting, subtitles, clean, titles, decorative

        var id: Self { self }

        var title: String {
            switch self {
            case .handwriting: "Handwriting"
            case .subtitles: "Subtitles"
            case .clean: "Clean"
            case .titles: "Titles"
            case .decorative: "Decorative"
            }
        }

        var symbol: String {
            switch self {
            case .handwriting: "signature"
            case .subtitles: "captions.bubble"
            case .clean: "textformat"
            case .titles: "textformat.size.larger"
            case .decorative: "sparkles"
            }
        }

        var summary: String {
            switch self {
            case .handwriting: "Written as if by hand, stroke by stroke."
            case .subtitles: "Bold and plain, easy to read at a glance."
            case .clean: "Simple lines for labels and notes."
            case .titles: "Classic and display styles for headings."
            case .decorative: "Ornate and playful, for a touch of style."
            }
        }
    }

    /// PostScript name for outline fonts, bundle resource name for single-line fonts.
    let postScriptName: String
    let displayName: String
    var kind = Kind.outline
    var category = Category.titles

    var id: String { postScriptName }

    private static func line(_ name: String, _ display: String, _ category: Category) -> OutlineFont {
        OutlineFont(postScriptName: name, displayName: display, kind: .singleLine, category: category)
    }

    private static func outline(_ name: String, _ display: String, _ category: Category) -> OutlineFont {
        OutlineFont(postScriptName: name, displayName: display, kind: .outline, category: category)
    }

    /// Every font, grouped by category in picker order. Outline fonts the device
    /// doesn't have are left out.
    static let all: [OutlineFont] = [
        line("HersheyScript", "Script", .handwriting),
        line("HersheyScriptMedium", "Script Bold", .handwriting),
        line("CursiveScript", "Cursive", .handwriting),
        line("EMSAllure", "Allure", .handwriting),
        line("EMSFelix", "Felix", .handwriting),
        line("EMSElfin", "Elfin", .handwriting),
        outline("SnellRoundhand-Bold", "Snell", .handwriting),
        outline("BradleyHandITCTT-Bold", "Hand", .handwriting),
        outline("Noteworthy-Bold", "Note", .handwriting),

        line("HersheySansBold", "Sans Bold", .subtitles),
        outline("TikTokSans16pt-Bold", "TikTok Sans", .subtitles),
        outline("Montserrat-ExtraBold", "Montserrat", .subtitles),
        outline("HelveticaNeue-Bold", "Helvetica", .subtitles),
        outline("Arial-BoldMT", "Arial", .subtitles),
        outline("Verdana-Bold", "Verdana", .subtitles),
        outline("AtkinsonHyperlegible-Bold", "Atkinson", .subtitles),

        line("ReliefSingleLine", "Relief", .clean),
        line("EMSReadability", "Readable", .clean),
        line("EMSReadabilityItalic", "Readable It.", .clean),
        line("HersheySans", "Sans", .clean),
        line("EMSTech", "Tech", .clean),
        outline("AvenirNext-Heavy", "Heavy", .clean),

        outline("Futura-Bold", "Futura", .titles),
        outline("Didot-Bold", "Didot", .titles),
        outline("Georgia-BoldItalic", "Georgia", .titles),
        outline("Copperplate-Bold", "Plate", .titles),
        outline("AmericanTypewriter-Bold", "Typewriter", .titles),
        line("HersheySerifBold", "Serif Bold", .titles),
        line("HersheySerifBoldItalic", "Serif Bold It.", .titles),
        line("HersheySerif", "Serif", .titles),
        line("EMSNixish", "Nixish", .titles),
        line("EMSNixishItalic", "Nixish It.", .titles),

        line("HersheyGothic", "Gothic", .decorative),
        line("HersheyGothicItalian", "Gothic Round", .decorative),
        line("EMSOsmotron", "Osmotron", .decorative),
        outline("Zapfino", "Zapfino", .decorative),
        outline("MarkerFelt-Wide", "Marker", .decorative),
        outline("Chalkduster", "Chalk", .decorative),
    ].filter { $0.kind == .singleLine || UIFont(name: $0.postScriptName, size: 12) != nil }

    static var singleLine: [OutlineFont] { all.filter { $0.kind == .singleLine } }

    static func fonts(in category: Category) -> [OutlineFont] {
        all.filter { $0.category == category }
    }

    static var defaultFont: OutlineFont {
        all.first ?? OutlineFont(postScriptName: "Helvetica-Bold", displayName: "Helvetica")
    }

    private static let byName = Dictionary(all.map { ($0.postScriptName, $0) }, uniquingKeysWith: { first, _ in first })

    static func named(_ name: String) -> OutlineFont? {
        byName[name]
    }

    /// Makes the outline fonts shipped in the app (subtitle faces) available by name.
    /// Call once at launch, before the font list is first used.
    static func registerBundledFonts() {
        for resource in ["TikTokSans16pt-Bold", "Montserrat-ExtraBold", "AtkinsonHyperlegible-Bold"] {
            guard let url = Bundle.main.url(forResource: resource, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
