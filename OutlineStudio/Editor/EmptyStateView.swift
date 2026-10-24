//
//  EmptyStateView.swift
//  OutlineStudio
//

import SwiftUI

/// First screen: a looping demo of the outline effect and ways to bring in footage.
struct EmptyStateView: View {
    @Environment(\.self) private var environment
    let isLoading: Bool
    let choosePhoto: () -> Void
    let browseFiles: () -> Void
    let useSample: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            demo
                .frame(height: 170)

            VStack(spacing: 8) {
                Text("Draw text onto your video")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Words write themselves onto your footage, one stroke at a time. Pick a clip to start.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            VStack(spacing: 10) {
                Button(action: choosePhoto) {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(Theme.onAccent)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 2))
                }
                HStack(spacing: 10) {
                    secondaryButton("Browse Files", symbol: "folder", action: browseFiles)
                    secondaryButton("Sample clip", symbol: "sparkles.tv", action: useSample)
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .padding(.horizontal, 24)
            .frame(maxWidth: 440)

            Spacer()
        }
        .overlay {
            if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
            }
        }
    }

    private var demo: some View {
        TimelineView(.animation) { timeline in
            let loop = 4.0
            let time = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: loop)
            Canvas { context, size in
                var overlay = TextOverlay()
                overlay.text = "Outline"
                overlay.fontName = OutlineFont.defaultFont.postScriptName
                overlay.relativeSize = 0.55
                overlay.strokeWidthRatio = 0.02
                overlay.strokeColor = Theme.accent.resolve(in: environment).cgColor
                overlay.fillColor = Theme.textPrimary.resolve(in: environment).cgColor
                overlay.startTime = 0.2
                overlay.drawDuration = 2.2
                overlay.endTime = loop - 0.35
                context.withCGContext { cgContext in
                    OutlineRenderer.draw(overlay, at: time, in: cgContext, videoSize: size)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func secondaryButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(Theme.textPrimary)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 2))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control + 2).strokeBorder(Theme.hairline))
        }
    }
}
