import SwiftUI

enum PadAppearance {
    #if os(macOS)
    static let accent = Color(nsColor: .controlAccentColor)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    #else
    static let accent = Color(uiColor: .systemBlue)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    #endif
}

struct PadBackdrop: View {
    var body: some View {
        PadAppearance.background
            .ignoresSafeArea().allowsHitTesting(false)
    }
}

struct PadGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(PadAppearance.surface, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.primary.opacity(0.1)))
        } else if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.05), radius: 16, y: 6)
        }
    }
}

extension View {
    func padGlass() -> some View { modifier(PadGlass()) }
}
