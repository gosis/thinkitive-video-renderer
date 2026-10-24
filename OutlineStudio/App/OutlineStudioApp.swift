//
//  OutlineStudioApp.swift
//  OutlineStudio
//

import SwiftUI

@main
struct OutlineStudioApp: App {
    @AppStorage(AppearancePreference.storageKey) private var appearance: AppearancePreference = .system

    var body: some Scene {
        WindowGroup {
            EditorView()
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.accent)
        }
    }
}
