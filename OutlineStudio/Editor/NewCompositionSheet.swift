//
//  NewCompositionSheet.swift
//  OutlineStudio
//

import SwiftUI

/// Asks for a length (and, for a blank video, a shape), then starts a composition
/// from black or from a picked photo.
struct NewCompositionSheet: View {
    /// When set, the video shows this photo and takes its shape.
    var image: UIImage?
    let create: (_ duration: Double, _ shape: BlankClip.Shape) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var duration = 10.0
    @State private var shape = BlankClip.Shape.portrait

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(image == nil ? "New blank video" : "Photo to video")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(image == nil ? "A black canvas to write text on." : "How long should the photo stay on screen?")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            LabeledSlider(title: "Length",
                          value: Binding(get: { duration }, set: { duration = $0.rounded() }),
                          range: BlankClip.durationRange,
                          format: { "\(Int($0)) s" })

            if image == nil {
                Picker("Shape", selection: $shape) {
                    ForEach(BlankClip.Shape.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Button {
                create(duration, shape)
                dismiss()
            } label: {
                Text("Create")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.accent)
            .controlSize(.large)
        }
        .padding(24)
        .presentationDetents([.height(image == nil ? 340 : 520)])
        .onAppear { if image != nil { duration = 5 } }
    }
}
