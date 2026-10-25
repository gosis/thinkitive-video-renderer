//
//  OutlineStudioApp.swift
//  OutlineStudio
//

import SwiftUI

@main
struct OutlineStudioApp: App {
    @AppStorage(AppearancePreference.storageKey) private var appearance: AppearancePreference = .system

    init() {
        // Bundled subtitle fonts must be registered before any font list is built
        OutlineFont.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            EditorView()
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.accent)
        }
    }
}
