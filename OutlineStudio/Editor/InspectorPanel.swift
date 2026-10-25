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
    @State private var fontCategory = OutlineFont.Category.handwriting

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
        .glassPanel()
    }

    // MARK: Text

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Type something", text: $overlay.text, axis: .vertical)
                .lineLimit(1...3)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .padding(10)
                .background(Theme.inset, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .accessibilityIdentifier("overlayText")

            fontPicker
        }
    }

    /// Fonts grouped by use: pick a group, then a font in it.
    private var fontPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(OutlineFont.Category.allCases) { category in
                        categoryPill(category)
                    }
                }
            }

            Text(fontCategory.summary)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(OutlineFont.fonts(in: fontCategory)) { font in
                        fontChip(font)
                    }
                }
            }
            .id(fontCategory)
        }
        .onAppear { fontCategory = overlay.font.category }
    }

    private func categoryPill(_ category: OutlineFont.Category) -> some View {
        let isShown = category == fontCategory
        // A dot marks the group holding the current font when another group is shown
        let holdsCurrent = category == overlay.font.category && !isShown
        return Button {
            fontCategory = category
        } label: {
            HStack(spacing: 5) {
                Image(systemName: category.symbol)
                Text(category.title)
                if holdsCurrent {
                    Circle().fill(Theme.accent).frame(width: 5, height: 5)
                }
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 11)
            .frame(height: 30)
            .foregroundStyle(isShown ? Theme.accent : Theme.textSecondary)
            .background(isShown ? Theme.accent.opacity(0.18) : Theme.inset, in: Capsule())
            .overlay(Capsule().strokeBorder(isShown ? Theme.accent.opacity(0.6) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.title) fonts")
        .accessibilityAddTraits(isShown ? .isSelected : [])
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 72, height: 60)
            .overlay(alignment: .topTrailing) {
                // Single-line fonts draw with one pen line and have no fill
                if font.kind == .singleLine {
                    Image(systemName: "pencil.line")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(5)
                }
            }
            .background(isSelected ? Theme.accent.opacity(0.18) : Theme.inset,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control)
                .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(font.displayName), \(font.kind.title)")
        .accessibilityIdentifier("font-\(font.postScriptName)")
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
            Picker("Writing", selection: $overlay.writingPace) {
                ForEach(WritingPace.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            captionNote(overlay.writingPace == .smooth
                        ? "The pen writes steadily through each caption, keeping up with the speech."
                        : "Each word writes itself in the moment it's spoken.")
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
