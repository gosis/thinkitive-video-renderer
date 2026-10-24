//
//  PreviewCanvas.swift
//  OutlineStudio
//

import AVFoundation
import SwiftUI

/// Video preview with live overlays. Overlays can be selected with a tap and moved by dragging.
struct PreviewCanvas: View {
    @Bindable var model: EditorModel
    @State private var dragOrigin: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let videoSize = fittedSize(in: proxy.size)

            ZStack {
                PlayerLayerView(player: model.player)

                Canvas { context, size in
                    context.withCGContext { cgContext in
                        for overlay in model.renderedOverlays {
                            OutlineRenderer.draw(overlay, at: model.currentTime, in: cgContext, videoSize: size)
                        }
                    }
                }
                .allowsHitTesting(false)

                handles(videoSize: videoSize)
            }
            .frame(width: videoSize.width, height: videoSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    /// The video's aspect-fit size, or zero while the container has no area.
    private func fittedSize(in container: CGSize) -> CGSize {
        guard container.width > 0, container.height > 0 else { return .zero }
        return AVMakeRect(aspectRatio: model.renderSize, insideRect: CGRect(origin: .zero, size: container)).size
    }

    private func handles(videoSize: CGSize) -> some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissKeyboard()
                    model.selectedID = nil
                    model.selectedCaptionID = nil
                }

            ForEach($model.overlays) { $overlay in
                handle(for: overlay, videoSize: videoSize, isSelected: overlay.id == model.selectedID,
                       color: Theme.accent,
                       select: { model.selectedID = overlay.id },
                       move: { overlay.position = $0 })
            }

            // Captions share one position, so dragging any of them moves them all
            ForEach(visibleCaptions) { caption in
                handle(for: caption, videoSize: videoSize, isSelected: caption.id == model.selectedCaptionID,
                       color: Theme.caption,
                       select: { model.selectedCaptionID = caption.id },
                       move: { model.moveCaptions(to: $0) })
            }
        }
        .frame(width: videoSize.width, height: videoSize.height)
    }

    /// Captions on screen now; only those can be tapped or dragged.
    private var visibleCaptions: [TextOverlay] {
        model.captionOverlays.filter { caption in
            model.currentTime >= caption.startTime && caption.opacity(at: model.currentTime) > 0
        }
    }

    private func handle(for overlay: TextOverlay, videoSize: CGSize, isSelected: Bool, color: Color,
                        select: @escaping () -> Void, move: @escaping (CGPoint) -> Void) -> some View {
        let frame = overlay.frame(in: videoSize)
        return Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .frame(width: max(frame.width, 44), height: max(frame.height, 44))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(color, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
            }
            .position(x: frame.midX, y: frame.midY)
            .onTapGesture(perform: select)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let origin = dragOrigin ?? overlay.position
                        if dragOrigin == nil {
                            dragOrigin = origin
                            select()
                        }
                        move(CGPoint(x: min(max(origin.x + value.translation.width / videoSize.width, 0), 1),
                                     y: min(max(origin.y + value.translation.height / videoSize.height, 0), 1)))
                    }
                    .onEnded { _ in dragOrigin = nil }
            )
    }
}
