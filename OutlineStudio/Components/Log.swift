//
//  Log.swift
//  OutlineStudio
//

import OSLog

/// Unified logging, visible in Console.app and device logs under the "Inkcap" category.
enum Log {
    static let app = Logger(subsystem: "com.gintsosis.outlinestudio", category: "Inkcap")
}
