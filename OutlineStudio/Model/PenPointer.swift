//
//  PenPointer.swift
//  OutlineStudio
//

/// A marker that rides on the point currently being drawn, like a pen tip.
enum PenPointer: String, CaseIterable, Identifiable, Codable {
    case off, dot, spark, comet, pencil

    var id: Self { self }

    var title: String {
        switch self {
        case .off: "Off"
        case .dot: "Glowing dot"
        case .spark: "Spark"
        case .comet: "Comet"
        case .pencil: "Pencil"
        }
    }

    var symbol: String {
        switch self {
        case .off: "circle.slash"
        case .dot: "circle.fill"
        case .spark: "sparkle"
        case .comet: "wand.and.rays"
        case .pencil: "pencil"
        }
    }
}
