//
//  TimelineStrip.swift
//  OutlineStudio
//

import SwiftUI

/// Ruler plus one lane per overlay showing when it is on screen.
///
/// Tapping or dragging anywhere on the strip moves the playhead; tapping a block
/// also selects its text or caption.
struct TimelineStrip: View {
    @Bindable var model: EditorModel

    private let rulerHeight: CGFloat = 26
    private let rulerSpacing: CGFloat = 6
    private let laneSpacing: CGFloat = 4
    private let maxLaneHeight: CGFloat = 28
    private let minLaneHeight: CGFloat = 10
    /// Lanes shrink to fit within this height instead of scrolling.
    private let maxLanesHeight: CGFloat = 92

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .topLeading) {
                VStack(spacing: rulerSpacing) {
                    ruler(width: width)
                    lanes(width: width)
                }

                playhead(at: x(for: model.currentTime, width: width))
            }
            .contentShape(Rectangle())
            // A finger wobbles a few points while tapping; only a deliberate drag scrubs
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in scrub(toX: value.location.x, width: width) }
            )
            // A tap anywhere moves the playhead there, alongside selecting a tapped block
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in scrub(toX: value.location.x, width: width) }
            )
        }
        .frame(height: rulerHeight + rulerSpacing + lanesHeight)
    }

    // MARK: Layout

    /// Text lanes plus one shared lane for captions.
    private var laneCount: Int {
        max(model.overlays.count + (model.captionLayer == nil ? 0 : 1), 1)
    }

    private var laneHeight: CGFloat {
        let count = CGFloat(laneCount)
        let fitted = (maxLanesHeight - (count - 1) * laneSpacing) / count
        return min(max(fitted, minLaneHeight), maxLaneHeight)
    }

    private var lanesHeight: CGFloat {
        let count = CGFloat(laneCount)
        return count * laneHeight + (count - 1) * laneSpacing
    }

    private func x(for time: Double, width: CGFloat) -> CGFloat {
        guard model.duration > 0 else { return 0 }
        return CGFloat(time / model.duration) * width
    }

    private func scrub(toX x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        dismissKeyboard()
        model.scrub(to: Double(min(max(x / width, 0), 1)) * model.duration)
    }

    // MARK: Pieces

    private func playhead(at x: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Grab handle sitting on the ruler
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.playhead)
                .frame(width: 12, height: 16)
            Rectangle()
                .fill(Theme.playhead)
                .frame(width: 2)
        }
        .frame(width: 12)
        .offset(x: x - 6)
        .allowsHitTesting(false)
    }

    private func ruler(width: CGFloat) -> some View {
        Canvas { context, size in
            guard model.duration > 0 else { return }
            let step = model.duration > 20 ? 5.0 : (model.duration > 8 ? 2.0 : 1.0)
            var second = 0.0
            while second <= model.duration {
                let x = CGFloat(second / model.duration) * size.width
                context.fill(Path(CGRect(x: x, y: size.height - 8, width: 1, height: 8)),
                             with: .color(Theme.textSecondary.opacity(0.6)))
                context.draw(Text("\(Int(second))s").font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary),
                             at: CGPoint(x: x + 3, y: 7), anchor: .leading)
                second += step
            }
        }
        .frame(height: rulerHeight)
        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in scrub(toX: value.location.x, width: width) }
        )
        .accessibilityElement()
        .accessibilityLabel("Playhead")
        .accessibilityValue(model.currentTime.timecode)
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.5 : -0.5
            model.scrub(to: model.currentTime + step)
        }
    }

    private func lanes(width: CGFloat) -> some View {
        VStack(spacing: laneSpacing) {
            if let layer = model.captionLayer {
                captionLane(layer, width: width)
            }
            if model.overlays.isEmpty && model.captionLayer == nil {
                Text("No text yet")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: laneHeight)
            }
            ForEach(model.overlays) { overlay in
                clip(for: overlay, width: width)
            }
        }
        .frame(height: lanesHeight, alignment: .top)
    }

    /// Every caption as a block on one lane; the solid part is when its words are spoken.
    private func captionLane(_ layer: CaptionLayer, width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Theme.inset)

            // Each block spans exactly when its caption is on screen, so blocks never overlap
            ForEach(Array(zip(layer.captions, model.captionOverlays)), id: \.0.id) { caption, overlay in
                let start = x(for: overlay.startTime, width: width)
                let shown = (overlay.endTime ?? model.duration) + TextOverlay.fadeOutDuration
                let end = x(for: min(shown, model.duration), width: width)
                let isSelected = caption.id == model.selectedCaptionID

                RoundedRectangle(cornerRadius: 5)
                    .fill(Theme.caption.opacity(isSelected ? 1 : 0.55))
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(isSelected ? Theme.onAccent.opacity(0.9) : .clear, lineWidth: 1.5))
                    .frame(width: max(end - start - 2, 6))
                    .contentShape(Rectangle())
                    .highPriorityGesture(TapGesture().onEnded { model.selectCaption(caption.id) })
                    .accessibilityElement()
                    .accessibilityLabel("Caption \(caption.text)")
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    // Padding rather than an offset, so the tap area sits where the block is drawn
                    .padding(.leading, start)
            }
        }
        .frame(height: laneHeight)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func clip(for overlay: TextOverlay, width: CGFloat) -> some View {
        let start = x(for: overlay.startTime, width: width)
        let end = x(for: overlay.endTime ?? model.duration, width: width)
        let drawEnd = x(for: overlay.startTime + overlay.drawDuration, width: width)
        let isSelected = overlay.id == model.selectedID
        let color = isSelected ? Theme.accent : Theme.clip

        return ZStack(alignment: .leading) {
            Rectangle().fill(Theme.inset)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.35))
                // The solid part shows how long the outline takes to draw
                RoundedRectangle(cornerRadius: 6)
                    .fill(color)
                    .frame(width: max(min(drawEnd, end) - start, 6))
                if laneHeight >= 20 {
                    Text(overlay.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? " ")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.onAccent)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                }
            }
            .frame(width: max(end - start, 12))
            .padding(.leading, start)
        }
        .frame(height: laneHeight)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .highPriorityGesture(TapGesture().onEnded { model.selectedID = overlay.id })
        .accessibilityElement()
        .accessibilityLabel("Text \(overlay.text)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
