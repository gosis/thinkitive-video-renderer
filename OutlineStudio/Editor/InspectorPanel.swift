//
//  InspectorPanel.swift
//  OutlineStudio
//

import SwiftUI

/// Properties of the selected overlay, grouped into Text, Style and Timing tabs.
struct InspectorPanel: View {
    enum Tab: String, CaseIterable, Identifiable {
        case text = "Text", style = "Style", timing = "Timing"
        var id: Self { self }
    }

    @Binding var overlay: TextOverlay
    let duration: Double
    /// Captions write themselves along with the speech and share one style.
    var isCaption = false
    @State private var tab = Tab.text

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Section", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch tab {
            case .text: textSection
            case .style: styleSection
            case .timing: timingSection
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel).strokeBorder(Theme.hairline))
    }

    // MARK: Text

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Type something", text: $overlay.text, axis: .vertical)
                .lineLimit(1...3)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .padding(10)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                .accessibilityIdentifier("overlayText")

            fontRow
        }
    }

    /// One scrolling row: single-line fonts first, then outline fonts.
    private var fontRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                fontGroup(.singleLine, fonts: OutlineFont.singleLine)
                Divider().frame(height: 48)
                fontGroup(.outline, fonts: OutlineFont.outline)
            }
        }
    }

    private func fontGroup(_ kind: OutlineFont.Kind, fonts: [OutlineFont]) -> some View {
        HStack(spacing: 8) {
            Text(kind.shortTitle.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: 14)
                .accessibilityHidden(true)
            ForEach(fonts) { font in
                fontChip(font)
            }
        }
    }

    private func fontChip(_ font: OutlineFont) -> some View {
        let isSelected = font.postScriptName == overlay.fontName
        return Button {
            select(font)
        } label: {
            VStack(spacing: 2) {
                FontSwatch(font: font, color: Theme.textPrimary)
                    .frame(width: 60, height: 30)
                Text(font.displayName)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 68, height: 60)
            .background(isSelected ? Theme.accent.opacity(0.14) : Theme.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control)
                .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(font.displayName), \(font.kind.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func select(_ font: OutlineFont) {
        // Single-line strokes need a heavier line than outlines to read well
        if font.kind != overlay.font.kind {
            overlay.strokeWidthRatio = font.kind.defaultStrokeWidthRatio
        }
        overlay.fontName = font.postScriptName
    }

    // MARK: Style

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledSlider(title: "Size",
                          value: cgBinding(\.relativeSize),
                          range: 0.04...0.4,
                          format: { "\(Int($0 * 100))%" })
            LabeledSlider(title: isSingleLine ? "Line width" : "Outline width",
                          value: cgBinding(\.strokeWidthRatio),
                          range: 0.005...0.12,
                          format: { String(format: "%.1f", $0 * 100) })

            HStack(spacing: 16) {
                ColorPicker(isSingleLine ? "Line" : "Outline", selection: $overlay.strokeColor, supportsOpacity: false)
                if !isSingleLine {
                    Divider().frame(height: 24)
                    Toggle("Fill", isOn: $overlay.fillEnabled)
                        .fixedSize()
                    ColorPicker("Fill colour", selection: $overlay.fillColor, supportsOpacity: false)
                        .labelsHidden()
                        .disabled(!overlay.fillEnabled)
                        .opacity(overlay.fillEnabled ? 1 : 0.4)
                }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 16) {
                Toggle("Shadow", isOn: $overlay.shadowEnabled)
                    .fixedSize()
                Divider().frame(height: 24)
                Toggle("Background", isOn: $overlay.backgroundEnabled)
                    .fixedSize()
                ColorPicker("Background colour", selection: $overlay.backgroundColor, supportsOpacity: true)
                    .labelsHidden()
                    .disabled(!overlay.backgroundEnabled)
                    .opacity(overlay.backgroundEnabled ? 1 : 0.4)
            }
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)

            HStack {
                Text("Pointer")
                Spacer()
                Picker("Pointer", selection: $overlay.pointer) {
                    ForEach(PenPointer.allCases) { pointer in
                        Label(pointer.title, systemImage: pointer.symbol).tag(pointer)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("pointerMenu")
            }
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)

            if isCaption {
                captionNote("Style changes apply to every caption.")
            } else {
                drawStylePicker
            }
        }
    }

    private var drawStylePicker: some View {
        Picker("Draw", selection: $overlay.style) {
            ForEach(TextOverlay.DrawStyle.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: Timing

    @ViewBuilder
    private var timingSection: some View {
        if isCaption {
            captionTimingSection
        } else {
            textTimingSection
        }
    }

    /// A caption's span; its words keep their spoken rhythm within it.
    private var captionTimingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledSlider(title: "Start",
                          value: $overlay.startTime,
                          range: 0...max(duration - 0.1, 0.1),
                          format: \.timecode)
            LabeledSlider(title: "Fade out at",
                          value: Binding(get: { overlay.endTime ?? duration }, set: { overlay.endTime = $0 }),
                          range: min(overlay.startTime + 0.2, duration)...max(duration, overlay.startTime + 0.3),
                          format: \.timecode)
            captionNote("Each word writes itself as it's spoken.")
        }
    }

    private func captionNote(_ text: String) -> some View {
        Label(text, systemImage: "captions.bubble")
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
    }

    private var textTimingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledSlider(title: "Start",
                          value: startBinding,
                          range: 0...max(duration - 0.1, 0.1),
                          format: \.timecode)
            LabeledSlider(title: "Draw time",
                          value: $overlay.drawDuration,
                          range: 0.2...max(min(duration, 10), 0.5),
                          format: { String(format: "%.1fs", $0) })

            Toggle("Hold until the end", isOn: holdBinding)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            if let endTime = overlay.endTime {
                LabeledSlider(title: "Fade out at",
                              value: Binding(get: { endTime }, set: { overlay.endTime = $0 }),
                              range: min(overlay.startTime + 0.1, duration)...max(duration, overlay.startTime + 0.2),
                              format: \.timecode)
            }

            Picker("Easing", selection: $overlay.easing) {
                ForEach(Easing.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var isSingleLine: Bool {
        overlay.font.kind == .singleLine
    }

    private var startBinding: Binding<Double> {
        Binding {
            overlay.startTime
        } set: { start in
            overlay.startTime = start
            if let endTime = overlay.endTime, endTime < start + 0.1 {
                overlay.endTime = min(start + 0.1, duration)
            }
        }
    }

    private var holdBinding: Binding<Bool> {
        Binding {
            overlay.endTime == nil
        } set: { hold in
            overlay.endTime = hold ? nil : min(duration, overlay.startTime + overlay.drawDuration + 1.5)
        }
    }

    private func cgBinding(_ keyPath: WritableKeyPath<TextOverlay, CGFloat>) -> Binding<Double> {
        Binding {
            Double(overlay[keyPath: keyPath])
        } set: {
            overlay[keyPath: keyPath] = CGFloat($0)
        }
    }
}

/// "Aa" drawn in a font through the same renderer as the video, so stroke fonts preview correctly.
private struct FontSwatch: View {
    let font: OutlineFont
    let color: Color
    @Environment(\.self) private var environment

    var body: some View {
        Canvas { context, size in
            var sample = TextOverlay()
            sample.text = "Aa"
            sample.fontName = font.postScriptName
            sample.relativeSize = 0.72
            sample.strokeWidthRatio = font.kind == .singleLine ? 0.07 : 0.01
            let resolved = color.resolve(in: environment).cgColor
            sample.strokeColor = resolved
            sample.fillColor = resolved
            sample.drawDuration = 0
            context.withCGContext { cgContext in
                OutlineRenderer.draw(sample, at: 1, in: cgContext, videoSize: size)
            }
        }
    }
}
