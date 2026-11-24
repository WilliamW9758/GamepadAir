import SwiftUI

struct PadActionStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.medium))
            .padding(.horizontal, 18).padding(.vertical, 10)
            .foregroundStyle(prominent ? Color.white : configuration.role == .destructive ? Color.red : Color.primary)
            .background(prominent ? (configuration.role == .destructive ? Color.red : PadAppearance.accent) : Color.primary.opacity(0.07), in: Capsule())
            .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.4)
            .contentShape(Capsule())
    }
}
