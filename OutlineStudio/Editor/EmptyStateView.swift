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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                overlay.text = "Inkcap"
                // Connected and slanted, like a signature; echoes the icon's loop
                overlay.fontName = "CursiveScript"
                overlay.relativeSize = 0.5
                overlay.strokeWidthRatio = 0.045
                overlay.pointer = .dot
                overlay.easing = .easeInOut
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

/// Soft brand-coloured light drifting slowly behind the start screen, plus faint
/// handwritten loops, so the backdrop feels alive without competing with the title.
struct AmbientGlow: View {
    @Environment(\.colorScheme) private var colorScheme

    private struct Light {
        let color: Color
        let x: Double, y: Double, radius: Double
        let speed: Double, phase: Double
    }

    private let lights = [
        Light(color: Color(light: 0xFF9F2E, dark: 0xFF9F2E), x: 0.2, y: 0.18, radius: 0.55, speed: 0.11, phase: 0),
        Light(color: Color(light: 0xFF5A4E, dark: 0xFF5A4E), x: 0.85, y: 0.35, radius: 0.6, speed: 0.08, phase: 2.1),
        Light(color: Color(light: 0xE4307A, dark: 0xE4307A), x: 0.3, y: 0.82, radius: 0.65, speed: 0.07, phase: 4.2),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let strength = colorScheme == .dark ? 0.32 : 0.22
                let extent = max(size.width, size.height)
                for light in lights {
                    let center = CGPoint(
                        x: size.width * (light.x + 0.08 * sin(time * light.speed + light.phase)),
                        y: size.height * (light.y + 0.06 * cos(time * light.speed * 1.3 + light.phase)))
                    let radius = extent * light.radius
                    context.fill(
                        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                               width: radius * 2, height: radius * 2)),
                        with: .radialGradient(Gradient(colors: [light.color.opacity(strength), light.color.opacity(0)]),
                                              center: center, startRadius: 0, endRadius: radius))
                }

                // Two faint pen loops sweeping across, echoing the logo
                let ink = (colorScheme == .dark ? Color.white : Theme.accent).opacity(colorScheme == .dark ? 0.05 : 0.07)
                for (index, offset) in [0.28, 0.74].enumerated() {
                    let y = size.height * offset
                    let drift = sin(time * 0.05 + Double(index) * 1.7) * 20
                    var loop = Path()
                    loop.move(to: CGPoint(x: -40, y: y + 30))
                    loop.addCurve(to: CGPoint(x: size.width * 0.55, y: y - 40 + drift),
                                  control1: CGPoint(x: size.width * 0.2, y: y + 60),
                                  control2: CGPoint(x: size.width * 0.5, y: y - 120))
                    loop.addCurve(to: CGPoint(x: size.width * 0.45, y: y + 10),
                                  control1: CGPoint(x: size.width * 0.6, y: y + 40),
                                  control2: CGPoint(x: size.width * 0.38, y: y + 60))
                    loop.addCurve(to: CGPoint(x: size.width + 40, y: y - 20 - drift),
                                  control1: CGPoint(x: size.width * 0.55, y: y - 30),
                                  control2: CGPoint(x: size.width * 0.8, y: y + 20))
                    context.stroke(loop, with: .color(ink), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
