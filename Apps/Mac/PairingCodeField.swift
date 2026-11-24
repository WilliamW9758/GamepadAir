import SwiftUI

/// One native editor keeps paste, deletion, keyboard navigation, and VoiceOver intact.
struct PairingCodeField: View {
    @Binding var code: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: Binding(get: { code }, set: {
            code = String(WirelessSettings.normalizedCode($0).prefix(6))
        }))
        .textFieldStyle(.plain)
        .font(.system(size: 28, design: .monospaced))
        .focused($focused)
        .opacity(0.02)
        .frame(width: 348, height: 60)
        .overlay {
            HStack(spacing: 8) {
                ForEach(0..<6) { index in
                    let digits = Array(code)
                    Text(index < digits.count ? String(digits[index]) : "")
                        .font(.system(size: 28, weight: .medium, design: .monospaced))
                        .frame(width: 50, height: 58)
                        .background(PadAppearance.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
                            focused && index == min(code.count, 5) ? PadAppearance.accent : Color.primary.opacity(0.14),
                            lineWidth: focused && index == min(code.count, 5) ? 2 : 1))
                }
            }.allowsHitTesting(false).accessibilityHidden(true)
        }
        .accessibilityLabel("Six-digit pairing code")
        .accessibilityHint("Enter or paste the code shown on your iPhone")
    }
}
