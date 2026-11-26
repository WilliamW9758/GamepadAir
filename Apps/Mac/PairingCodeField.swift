import SwiftUI

/// A visible native editor keeps the caret, selection and deletion aligned with the digits.
struct PairingCodeField: View {
    @Binding var code: String
    var body: some View {
        TextField("Six-digit code", text: Binding(get: { code }, set: {
            code = String(WirelessSettings.normalizedCode($0).prefix(6))
        }))
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 28, weight: .medium, design: .monospaced))
        .frame(width: 260, height: 60)
        .accessibilityLabel("Six-digit pairing code")
        .accessibilityHint("Enter or paste the code shown on your iPhone")
    }
}
