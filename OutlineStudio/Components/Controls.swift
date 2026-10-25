//
//  Controls.swift
//  OutlineStudio
//

import SwiftUI
import UIKit

/// Slider row with a label and a monospaced value readout.
struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: (Double) -> String = { String(format: "%.1f", $0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(format(value))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
            }
            .font(.subheadline)
            Slider(value: $value, in: range)
        }
    }
}

/// Round Liquid Glass icon button used in the transport bar and toolbar.
struct IconButton: View {
    let symbol: String
    let label: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        if prominent {
            button.buttonStyle(.glassProminent).tint(Theme.accent)
        } else {
            // Neutral, so only the main action carries the accent
            button.buttonStyle(.glass).foregroundStyle(Theme.textPrimary)
        }
    }

    private var button: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
    }
}

extension Double {
    /// `m:ss.cc`, as shown in editing timecodes.
    var timecode: String {
        let total = max(self, 0)
        let minutes = Int(total) / 60
        let seconds = Int(total) % 60
        let hundredths = Int((total - floor(total)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, hundredths)
    }
}

/// Resigns whichever text field is first responder.
@MainActor
func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
