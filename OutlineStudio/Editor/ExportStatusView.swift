//
//  ExportStatusView.swift
//  OutlineStudio
//

import SwiftUI

/// Modal card shown while a video renders and after it is saved.
struct ExportStatusView: View {
    let state: EditorModel.ExportState
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()

            VStack(spacing: 16) {
                switch state {
                case .idle:
                    EmptyView()
                case .rendering(let progress):
                    Text("Rendering")
                        .font(.headline)
                    ProgressView(value: progress)
                        .tint(Theme.accent)
                    Text("\(Int(progress * 100))%")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                case .saved:
                    result(symbol: "checkmark.circle.fill", color: Theme.clip,
                           title: "Saved to Photos", message: nil)
                case .failed(let message):
                    result(symbol: "exclamationmark.triangle.fill", color: Theme.accent,
                           title: "Export failed", message: message)
                }
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(24)
            .frame(width: 280)
            .glassPanel(cornerRadius: 28)
        }
    }

    @ViewBuilder
    private func result(symbol: String, color: Color, title: String, message: String?) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 40))
            .foregroundStyle(color)
        Text(title)
            .font(.headline)
        if let message {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        Button("Done", action: dismiss)
            .buttonStyle(.glassProminent)
            .tint(Theme.accent)
    }
}
